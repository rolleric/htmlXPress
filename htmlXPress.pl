#!/usr/bin/env perl -w
#
# htmlXPress, version 4.0 - to compress and format HTML files
# Copyright (c) 2000, tredje design - Eric Roller.
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.

my $version = "4.4";

# Version History
# ===============
# 2019-11-06  4.4
#    Adds support to set $debug in the site package.
#    The default $destination is now ".".
#
# 2018-06-23  4.3
#    Added an alternative marker style: <:nowrap:> ($hxpr_beg, $hxpr_end).
#    This is to avoid error markers in vim's syntax highlighting.
#
# 2016-03-12  4.2
#    User can supply an output file name with -out option.
#
# 2015-07-25  4.1
#    Changed the HTML entity encoding to an approach suggested
#    by Html::Entities (3.69).
#    Declared file encoding to be UTF-8.
#
# 2015-03-25  4.0
#    Repackaging for wider distribution.
#    Site file is now optional if ($site_package_name ne "").
#    Removed css_id compression.
#    Removed out-of-date syntax checking.
#
# 2015-02-14  3.0.3
#    Added "m" to "if (/abc/)" statements.
#    Also removing // comments if page uses <?php code ?>.
#    Using <span id="x"> as link target instead of <a name="x">.
#
# 2012-11-28  3.0.2
#    Added @attr_not_zero to allow hspace="0" in our code.
#
# 2012-08-06  3.0.1
#    Removed a "defined()" as suggested by Perl on Mountain Lion.
#
# 2006-11-12  3.0
#
#    Beginning re-code for proper use of Perl packages (site.pm).
#    Now using %file_table instead of clumsy @file_rules.
#    Retired obsolete MacPerl stuff.
#    Added handling of // php-comments.
#    Fixed a problem with undefined $outdir when --inplace is used.
#    Fixed a clash between PLIST and ordinary XML files ($isxml).
#    Changed default text creator BBEdit (R*ch) -> TextWrangler (!Rch).
#

use strict;
 no strict qw(refs);
use diagnostics;
use open ':encoding(utf8)';
use File::Basename;         # basename, dirname
use File::Spec::Functions;  # catdir, catfile, curdir
use Getopt::Long;           # GetOptions
use Pod::Usage;             # pod2usage
use Text::Wrap;             # wrap
use Unicode::Normalize;     # NFC


# =========================================================================
# Configuration
# =========================================================================
# The variables defined in the following can be customised using simple
# configuration files in the user's home directory: ~/.htmlxpressrc
# The file should contain simple Perl code like:
#
#       # htmlXPress configuration file
#
#       # Path to the SetFile executable.
#       $set_file_exec = "/Developer/Tools/SetFile";
#


# -------------------------------------------------------------------------
# hxpr_beg hxpr_end
#
# The HTML-like markers that are used to delimit custom macros.
# Example: <<nowrap>> or <:nowrap:>.

our $hxpr_beg = "(?:<<|<:)";
our $hxpr_end = "(?:>>|:>)";


# -------------------------------------------------------------------------
# add_banner
#
# A boolean as to whether to include a hmtlXPress version banner in the
# output file. This can also be changed on the command-line using -banner
# or -nobanner.

our $add_banner = 1;


# -------------------------------------------------------------------------
# curl_exec
#
# Contains the path to the curl executable. This is used to check links.
# We will call it using options: --head --silent -o tmp_file "href"

our $curl_exec = "/usr/bin/curl";


# -------------------------------------------------------------------------
# date_format
#
# The date-format options for POSIX::strftime.
# By default, we shall use the (sortable) ISO-8601 notation: YYYY-MM-DD.

our $date_format = "%Y-%m-%d";


# -------------------------------------------------------------------------
# default_creator
#
# The default Macintosh file creator code applied to the written files.
# Example:  "R*ch" for BBEdit, or "!Rch" for TextWrangler.

our $default_creator = "";


# -------------------------------------------------------------------------
# destination
#
# The default output directory, unless given at the command line using the
# -out argument.

our $destination = ".";


# -------------------------------------------------------------------------
# %file_table
#
# This table defines the default settings for how files are to be handled.
# The keys of the table correspond to the file extensions (e.g. "html" for
# "test.html". Each type, may define one or more of the following keywords
# (or inherit the settings from the "default" type):
#
#   creator     creator code (Mac OS 9), e.g. "!Rch" for TextWrangler,
#
#   info        a text string describing the file type,
#
#   textwidth   a column width for text wrapping, or '0' to disable it
#               (but not when javascript is embedded, nor when <pre> or
#               <<nowrap>> marker was found, see $wrap below),
#
#   compress    0: no compression,
#               1: HTML or CSS compression,
#               2: Additional type swapping, e.g. <strong> -> <b>
#
#   non_ascii   0: no handling of non-ASCII characters.
#               2: non-ASCII symbol formatting, e.g. umlauts like &auml;,
#
#   copy_from   reference to a different type definition whose settings
#               are imported (this key is removed during table expansion),
#
#   out         a new file name extension, e.g. "html" instead of "xml".
#
# NB. To add your own file types, define a file_table within your site
# package file (named $site_package_file.pm). Both file_table:s are combined
# and then expanded (where the "else_like" references are resolved and removed).

our %file_table = (

    # CSS: compress, else like "default".
    css => {
        info => "Cascading Style Sheet",
        compress => 1,
    },

    # HTML, compress, wrap lines to 80 characters.
    html => {
        info => "Hypert-text markup langage",
        compress => 2,
        non_ascii => 1,
        textwidth => 80,
    },

    # As above for HTML.
    htm => { copy_from => "html" },
    xml => { copy_from => "html" },

    php => {
        info => "PHP: Hypertext Preprocessor",
        copy_from => "html",
    },

    rss => {
        info => "Really Simple Syndication",
        copy_from => "html",
    },

    # Default: no compression, no line wrapping.
    default => {
        info => "default settings",
        compress => 0,
        creator => "",          # set to $default_creator below
        non_ascii => 0,
        textwidth => 0,
    },
);


# -------------------------------------------------------------------------
# set_file_exec
#
# Contains the path to the SetFile executable, if present. This is used to
# change Macintosh file creator codes (see "creator" in %file_table).
# If this variable does not point to an executable file, no creator codes
# will be set. In debug mode, an error would then be generated.
#
# It will be called with these options: SetFile -c <CODE> -t TEXT <file>
# where <CODE> is the creator code from the %file_table and <file> is our
# output file.
#
# Hint: Use "xcode-select -p" to find the Developer path within an Xcode.

our $set_file_exec = "/usr/bin/SetFile";


# -------------------------------------------------------------------------
# site_package_name
#
# The name of the ".pm" file with site-specific configurations and sub-
# routines. We prefer to use: "site". More on that below.

our $site_package_name = "";

# Use the default 'site' if a site.pm file exists in the current directory.
$site_package_name = "site" if (-f "./site.pm");


# -------------------------------------------------------------------------
# xml_lint_command
#
# Contains the path to the xmllint executable, if present, and any options
# that should be used with it.

our $xml_lint_command = "/usr/bin/xmllint -noout";


# -------------------------------------------------------------------------
# Date Formatting
# -------------------------------------------------------------------------

our $longdate = localtime();    # The locale-specific long date format.
our $date;                      # The custom date format.

if ($date_format ne "") {
    use POSIX qw(strftime);
    $date = strftime $date_format, localtime();

} else {
    $date = $longdate;
}


# -------------------------------------------------------------------------
# Load configuration file
# -------------------------------------------------------------------------
# The user may like to change the above variables (as described above).

do "$ENV{HOME}/.htmlxpressrc";


# -------------------------------------------------------------------------
# Internal variables
# -------------------------------------------------------------------------
# Name and copyright of this program.
my $prog = basename($0, "");
$prog =~ s/-\d+\.?\d*//;                # no -1.2 version suffixes
$prog =~ s/(?:script|hxp)/htmlXPress/;  # there used to be link names

my $copyright = "$prog ${version}, (c) 2000 tredje design - Eric Roller";


# =========================================================================
# Processing of Command-Line Options
# =========================================================================

my $debug = 0;      # Debug mode
my $href_check = 0; # Whether to pust all link destinations.
my $overwrite = 0;  # Allow overwriting the input file
my $help = 0;       # Whether to show the help page
my $lint = 1;       # Whether to do linting (XML only)
my $outdir;         # Output directory, set to "undef".
my $outfile;
my $verbose = 0;    # Verbose mode

GetOptions( 'banner!'           => \$add_banner,
            'href_check!'       => \$href_check,
            'debug!'            => \$debug,
            'help|usage+'       => \$help,
            'inplace|overwrite' => \$overwrite,
            'lint!'             => \$lint,
            'out=s'             => \$outdir,
            'verbose!'          => \$verbose ) or pod2usage(2);
pod2usage(-verbose => $help) if $help;


# -------------------------------------------------------------------------
# Check settings
# -------------------------------------------------------------------------

$verbose = 1 if $debug;

print "$prog, starting on $longdate\n" if $verbose;

if ($debug) {
    my $exec_path = (split /\s+/, $xml_lint_command)[0];
    print STDERR "Error: No executable at \$xml_lint_command: $xml_lint_command\n" if (! -x $exec_path);

    # Debug settings
    print "Variables:\n";
    foreach my $varname ( "add_banner", "curl_exec", "date_format",
                "default_creator", "destination", "hxpr_beg",
		"hxpr_end", "set_file_exec",
                "site_package_name", "xml_lint_command" ) {
        print "\t\$$varname = \"$$varname\";\n";
    }
}


# =========================================================================
# Load the site definitions
# =========================================================================
# Site-specific settings are stored in a ".pm" package which is usually
# located in the same directory as the source files (it is located via "."
# in @INC when htmlXPress is executed within that directory).
#
# It typically defines the pre_process, process, and post_process routines,
# but it may also define changes to the %file_table or any configuration
# variable.
#
# Its name can be set using the $site_package_name variable, for instance,
# in your .htmlxpressrc file. When $site_package_name is set to "site",
# we expect to find a "site.pm" file:
#
#       package site;  # assumes site.pm
#
#       use strict;
#       use warnings;
#
#       BEGIN {
#          our $VERSION     = 1.00;
#       }
#
#	our $debug = 0;
#
#       # Hard-coded destination directory:
#       our $destination = "/Library/Web Pages/";	# absolute path
#
#       # We don't like "YYY-MM-DD" dates
#       our $date_format = "%a %b %e %H:%M:%S %Y";      # for POSIX::strftime
#
#       sub pre_process($$)
#       {
#           my ($filename, $type) = @_;
#           # insert code here.
#       }
#
#       # This is where your site-specific code processing should be done.
#       sub process($$)
#       {
#           my ($filename, $type) = @_;
#           # insert code here.
#       }
#
#       sub post_process($$)
#       {
#           my ($filename, $type) = @_;
#           # insert code here.
#       }
#
#       1;  # don't forget to return a true value from the file

if ($site_package_name ne "") {
    print "+ use $site_package_name\n" if $debug;
    eval "use $site_package_name";

    if (defined(${"${site_package_name}::debug"}) && $debug) {
	print "+ \$${site_package_name}::debug = $debug\n";
	${"${site_package_name}::debug"} = $debug;
    }

    # Activate site-specific settings.
    foreach my $varname ( "add_banner", "curl_exec", "date_format",
                "default_creator", "destination", "hxpr_beg", "hxpr_end",
		"set_file_exec", "xml_lint_command" ) {
	if (defined(${"${site_package_name}::$varname"})) {
	    print "      + \$$varname\n" if $debug;
	    $$varname = ${"${site_package_name}::$varname"};
	}
    }
}


# -------------------------------------------------------------------------
# Import site-specifict data
# -------------------------------------------------------------------------
# This is where we merge the site's file table with our gobal one.

$file_table{"default"}{"creator"} = $default_creator;

if ($site_package_name ne "") {
    # Site-specific file_table entries take precedence.
    # New settings are appended.

    if (%{"${site_package_name}::file_table"}) {
        print "- Importing site-specific file table\n" if $verbose;
	my %table = %{"${site_package_name}::file_table"};

        foreach my $type ( keys(%table) ) {
            foreach my $code ( keys($table{"$type"}) ) {
                $file_table{$type}{$code} = $table{$type}{$code};
                print "\t$type.$code => $table{$type}{$code}\n" if $debug;
            }
        }
    }
}


# -------------------------------------------------------------------------
# Expanding the file table
# -------------------------------------------------------------------------

print "- Expanding the file table\n" if $verbose;

# All types will inherit settings from the "copy_from" reference type
# or the default type (but the master must have been expanded before
# this can happen.

my $done;

do {
    $done = 1;

    foreach my $type ( keys(%file_table) ) {
        next if $type eq "default";

        # If no "copy_from" entry is defined, use "copy_from" => "default"
        unless (defined($file_table{$type}{"copy_from"})) {
            $file_table{$type}{"copy_from"} = "default";
        }

        # Get the master
        my $from = $file_table{$type}{"copy_from"};

        # The master must exist!
        unless (defined($file_table{$from})) {
            print STDERR "Error: Refernce '$from' defined in '$type' is undefined.\n";
            $from = $file_table{$type}{"copy_from"} = "default";
        }

        # Only copy properties from the master after "default" has been propagated,
        # i.e. either the master is "default" or its master is "default".
        if (($from eq "default") ||
            (defined($file_table{$from}{"copy_from"}) && ($file_table{$from}{"copy_from"} eq "default"))) {

            foreach my $code ( keys(%{$file_table{$from}}) ) {
                unless (defined($file_table{$type}{$code})) {
                    $file_table{$type}{$code} = $file_table{$from}{$code};
                    print "\t$type.$code <= $from.$code ($file_table{$type}{$code})\n"
                        if $debug;
                }
            }

            # Mark this file type as expanded.
            # Other file types are now allowed to copy its values.
            $file_table{$type}{"copy_from"} = "default";

        } else {
            # The master type has not inherited the settings from
            # the default type yet - postpone this for one iteration.
            $done = 0;
        }
    }

} until $done;

# Clean up the file table - remove "copy_from" keys and the "default" type.
## delete $file_table{"default"};
foreach my $type ( keys(%file_table) ) {
    delete $file_table{$type}{"copy_from"};
}

# Present the results for -debug.
if ($debug) {
    print "Expanded file table:\n\n";
    foreach my $type ( keys(%file_table) ) {
        print "\t$type => {\n";
        foreach my $code ( keys(%{$file_table{$type}}) ) {
            print "\t    $code => \"$file_table{$type}{$code}\",\n";
        }
        print "\t},\n\n";
    }
}


# -------------------------------------------------------------------------
# Html entity encodings.
# -------------------------------------------------------------------------
# Follows the example of the Html::Encode module on CPAN:
# http://search.cpan.org/dist/HTML-Parser/lib/HTML/Entities.pm

our %char2entity = (
    # Some normal chars that have special meaning in SGML context
    '&'		=> 'amp',	# AMPERSAND
    '>'		=> 'gt',  	# GREATER-THAN SIGN
    '<'		=> 'lt',  	# LESS-THAN SIGN
    '"'		=> 'quot',	# QUOTATION MARK
    "'"		=> 'apos',	# APOSTROPHE

    # PUBLIC ISO 8879-1986//ENTITIES Added Latin 1//EN//HTML
    chr(192)	=> 'Agrave',  	# LATIN CAPITAL LETTER A WITH GRAVE
    chr(193)	=> 'Aacute',  	# LATIN CAPITAL LETTER A WITH ACUTE
    chr(194)	=> 'Acirc',  	# LATIN CAPITAL LETTER A WITH CIRCUMFLEX
    chr(195)	=> 'Atilde',  	# LATIN CAPITAL LETTER A WITH TILDE
    chr(196)	=> 'Auml',  	# LATIN CAPITAL LETTER A WITH DIAERESIS
    chr(197)	=> 'Aring',  	# LATIN CAPITAL LETTER A WITH RING ABOVE
    chr(198)	=> 'AElig',  	# LATIN CAPITAL LETTER AE
    chr(199)	=> 'Ccedil',  	# LATIN CAPITAL LETTER C WITH CEDILLA
    chr(200)	=> 'Egrave',  	# LATIN CAPITAL LETTER E WITH GRAVE
    chr(201)	=> 'Eacute',  	# LATIN CAPITAL LETTER E WITH ACUTE
    chr(202)	=> 'Ecirc',  	# LATIN CAPITAL LETTER E WITH CIRCUMFLEX
    chr(203)	=> 'Euml',  	# LATIN CAPITAL LETTER E WITH DIAERESIS
    chr(204)	=> 'Igrave',  	# LATIN CAPITAL LETTER I WITH GRAVE
    chr(205)	=> 'Iacute',  	# LATIN CAPITAL LETTER I WITH ACUTE
    chr(206)	=> 'Icirc',  	# LATIN CAPITAL LETTER I WITH CIRCUMFLEX
    chr(207)	=> 'Iuml',  	# LATIN CAPITAL LETTER I WITH DIAERESIS
    chr(208)	=> 'ETH',  	# LATIN CAPITAL LETTER ETH
    chr(209)	=> 'Ntilde',  	# LATIN CAPITAL LETTER N WITH TILDE
    chr(210)	=> 'Ograve',  	# LATIN CAPITAL LETTER O WITH GRAVE
    chr(211)	=> 'Oacute',  	# LATIN CAPITAL LETTER O WITH ACUTE
    chr(212)	=> 'Ocirc',  	# LATIN CAPITAL LETTER O WITH CIRCUMFLEX
    chr(213)	=> 'Otilde',  	# LATIN CAPITAL LETTER O WITH TILDE
    chr(214)	=> 'Ouml',  	# LATIN CAPITAL LETTER O WITH DIAERESIS
    chr(216)	=> 'Oslash',  	# LATIN CAPITAL LETTER O WITH STROKE
    chr(217)	=> 'Ugrave',  	# LATIN CAPITAL LETTER U WITH GRAVE
    chr(218)	=> 'Uacute',  	# LATIN CAPITAL LETTER U WITH ACUTE
    chr(219)	=> 'Ucirc',  	# LATIN CAPITAL LETTER U WITH CIRCUMFLEX
    chr(220)	=> 'Uuml',  	# LATIN CAPITAL LETTER U WITH DIAERESIS
    chr(221)	=> 'Yacute',  	# LATIN CAPITAL LETTER Y WITH ACUTE
    chr(222)	=> 'THORN',  	# LATIN CAPITAL LETTER THORN
    chr(223)	=> 'szlig',  	# LATIN SMALL LETTER SHARP S
    chr(224)	=> 'agrave',  	# LATIN SMALL LETTER A WITH GRAVE
    chr(225)	=> 'aacute',  	# LATIN SMALL LETTER A WITH ACUTE
    chr(226)	=> 'acirc',  	# LATIN SMALL LETTER A WITH CIRCUMFLEX
    chr(227)	=> 'atilde',  	# LATIN SMALL LETTER A WITH TILDE
    chr(228)	=> 'auml',  	# LATIN SMALL LETTER A WITH DIAERESIS
    chr(229)	=> 'aring',  	# LATIN SMALL LETTER A WITH RING ABOVE
    chr(230)	=> 'aelig',  	# LATIN SMALL LETTER AE
    chr(231)	=> 'ccedil',  	# LATIN SMALL LETTER C WITH CEDILLA
    chr(232)	=> 'egrave',  	# LATIN SMALL LETTER E WITH GRAVE
    chr(233)	=> 'eacute',  	# LATIN SMALL LETTER E WITH ACUTE
    chr(234)	=> 'ecirc',  	# LATIN SMALL LETTER E WITH CIRCUMFLEX
    chr(235)	=> 'euml',  	# LATIN SMALL LETTER E WITH DIAERESIS
    chr(236)	=> 'igrave',  	# LATIN SMALL LETTER I WITH GRAVE
    chr(237)	=> 'iacute',  	# LATIN SMALL LETTER I WITH ACUTE
    chr(238)	=> 'icirc',  	# LATIN SMALL LETTER I WITH CIRCUMFLEX
    chr(239)	=> 'iuml',  	# LATIN SMALL LETTER I WITH DIAERESIS
    chr(240)	=> 'eth',  	# LATIN SMALL LETTER ETH
    chr(241)	=> 'ntilde',  	# LATIN SMALL LETTER N WITH TILDE
    chr(242)	=> 'ograve',  	# LATIN SMALL LETTER O WITH GRAVE
    chr(243)	=> 'oacute',  	# LATIN SMALL LETTER O WITH ACUTE
    chr(244)	=> 'ocirc',  	# LATIN SMALL LETTER O WITH CIRCUMFLEX
    chr(245)	=> 'otilde',  	# LATIN SMALL LETTER O WITH TILDE
    chr(246)	=> 'ouml',  	# LATIN SMALL LETTER O WITH DIAERESIS
    chr(248)	=> 'oslash',  	# LATIN SMALL LETTER O WITH STROKE
    chr(249)	=> 'ugrave',  	# LATIN SMALL LETTER U WITH GRAVE
    chr(250)	=> 'uacute',  	# LATIN SMALL LETTER U WITH ACUTE
    chr(251)	=> 'ucirc',  	# LATIN SMALL LETTER U WITH CIRCUMFLEX
    chr(252)	=> 'uuml',  	# LATIN SMALL LETTER U WITH DIAERESIS
    chr(253)	=> 'yacute',  	# LATIN SMALL LETTER Y WITH ACUTE
    chr(254)	=> 'thorn',  	# LATIN SMALL LETTER THORN
    chr(255)	=> 'yuml',  	# LATIN SMALL LETTER Y WITH DIAERESIS

    # Some extra Latin 1 chars that are listed in the HTML3.2 draft (21-May-96)
    chr(160)	=> 'nbsp',  	# NO-BREAK SPACE
    chr(169)	=> 'copy',  	# COPYRIGHT SIGN
    chr(174)	=> 'reg',  	# REGISTERED SIGN

    # Additional ISO-8859/1 entities listed in rfc1866 (section 14)
    chr(161)	=> 'iexcl',	# INVERTED EXCLAMATION MARK
    chr(162)	=> 'cent',	# CENT SIGN
    chr(163)	=> 'pound',	# POUND SIGN
    chr(164)	=> 'curren',	# CURRENCY SIGN
    chr(165)	=> 'yen',	# YEN SIGN
    chr(166)	=> 'brvbar',	# BROKEN BAR
    chr(167)	=> 'sect',	# SECTION SIGN
    chr(168)	=> 'uml',	# DIAERESIS
    chr(170)	=> 'ordf',	# FEMININE ORDINAL INDICATOR
    chr(171)	=> 'laquo',	# LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
    chr(172)	=> 'not',	# NOT SIGN
    chr(173)	=> 'shy',	# SOFT HYPHEN
    chr(175)	=> 'macr',	# MACRON
    chr(176)	=> 'deg',	# DEGREE SIGN
    chr(177)	=> 'plusmn',	# PLUS-MINUS SIGN
    chr(178)	=> 'sup2',	# SUPERSCRIPT TWO
    chr(179)	=> 'sup3',	# SUPERSCRIPT THREE
    chr(180)	=> 'acute',	# ACUTE ACCENT
    chr(181)	=> 'micro',	# MICRO SIGN
    chr(182)	=> 'para',	# PILCROW SIGN
    chr(183)	=> 'middot',	# MIDDLE DOT
    chr(184)	=> 'cedil',	# CEDILLA
    chr(185)	=> 'sup1',	# SUPERSCRIPT ONE
    chr(186)	=> 'ordm',	# MASCULINE ORDINAL INDICATOR
    chr(187)	=> 'raquo',	# RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK
    chr(188)	=> 'frac14',	# VULGAR FRACTION ONE QUARTER
    chr(189)	=> 'frac12',	# VULGAR FRACTION ONE HALF
    chr(190)	=> 'frac34',	# VULGAR FRACTION THREE QUARTERS
    chr(191)	=> 'iquest',	# INVERTED QUESTION MARK
    chr(215)	=> 'times',	# MULTIPLICATION SIGN
    chr(247)	=> 'divide',	# DIVISION SIGN

    chr(338)	=> 'OElig',	# LATIN CAPITAL LIGATURE OE
    chr(339)	=> 'oelig',	# LATIN SMALL LIGATURE OE
    chr(352)	=> 'Scaron',	# LATIN CAPITAL LETTER S WITH CARON
    chr(353)	=> 'scaron',	# LATIN SMALL LETTER S WITH CARON
    chr(376)	=> 'Yuml',	# LATIN CAPITAL LETTER Y WITH DIAERESIS
    chr(402)	=> 'fnof',	# LATIN SMALL LETTER F WITH HOOK
    chr(710)	=> 'circ',	# MODIFIER LETTER CIRCUMFLEX ACCENT
    chr(732)	=> 'tilde',	# SMALL TILDE
    chr(913)	=> 'Alpha',	# GREEK CAPITAL LETTER ALPHA
    chr(914)	=> 'Beta',	# GREEK CAPITAL LETTER BETA
    chr(915)	=> 'Gamma',	# GREEK CAPITAL LETTER GAMMA
    chr(916)	=> 'Delta',	# GREEK CAPITAL LETTER DELTA
    chr(917)	=> 'Epsilon',	# GREEK CAPITAL LETTER EPSILON
    chr(918)	=> 'Zeta',	# GREEK CAPITAL LETTER ZETA
    chr(919)	=> 'Eta',	# GREEK CAPITAL LETTER ETA
    chr(920)	=> 'Theta',	# GREEK CAPITAL LETTER THETA
    chr(921)	=> 'Iota',	# GREEK CAPITAL LETTER IOTA
    chr(922)	=> 'Kappa',	# GREEK CAPITAL LETTER KAPPA
    chr(923)	=> 'Lambda',	# GREEK CAPITAL LETTER LAMDA
    chr(924)	=> 'Mu',	# GREEK CAPITAL LETTER MU
    chr(925)	=> 'Nu',	# GREEK CAPITAL LETTER NU
    chr(926)	=> 'Xi',	# GREEK CAPITAL LETTER XI
    chr(927)	=> 'Omicron',	# GREEK CAPITAL LETTER OMICRON
    chr(928)	=> 'Pi',	# GREEK CAPITAL LETTER PI
    chr(929)	=> 'Rho',	# GREEK CAPITAL LETTER RHO
    chr(931)	=> 'Sigma',	# GREEK CAPITAL LETTER SIGMA
    chr(932)	=> 'Tau',	# GREEK CAPITAL LETTER TAU
    chr(933)	=> 'Upsilon',	# GREEK CAPITAL LETTER UPSILON
    chr(934)	=> 'Phi',	# GREEK CAPITAL LETTER PHI
    chr(935)	=> 'Chi',	# GREEK CAPITAL LETTER CHI
    chr(936)	=> 'Psi',	# GREEK CAPITAL LETTER PSI
    chr(937)	=> 'Omega',	# GREEK CAPITAL LETTER OMEGA
    chr(945)	=> 'alpha',	# GREEK SMALL LETTER ALPHA
    chr(946)	=> 'beta',	# GREEK SMALL LETTER BETA
    chr(947)	=> 'gamma',	# GREEK SMALL LETTER GAMMA
    chr(948)	=> 'delta',	# GREEK SMALL LETTER DELTA
    chr(949)	=> 'epsilon',	# GREEK SMALL LETTER EPSILON
    chr(950)	=> 'zeta',	# GREEK SMALL LETTER ZETA
    chr(951)	=> 'eta',	# GREEK SMALL LETTER ETA
    chr(952)	=> 'theta',	# GREEK SMALL LETTER THETA
    chr(953)	=> 'iota',	# GREEK SMALL LETTER IOTA
    chr(954)	=> 'kappa',	# GREEK SMALL LETTER KAPPA
    chr(955)	=> 'lambda',	# GREEK SMALL LETTER LAMDA
    chr(956)	=> 'mu',	# GREEK SMALL LETTER MU
    chr(957)	=> 'nu',	# GREEK SMALL LETTER NU
    chr(958)	=> 'xi',	# GREEK SMALL LETTER XI
    chr(959)	=> 'omicron',	# GREEK SMALL LETTER OMICRON
    chr(960)	=> 'pi',	# GREEK SMALL LETTER PI
    chr(961)	=> 'rho',	# GREEK SMALL LETTER RHO
    chr(962)	=> 'sigmaf',	# GREEK SMALL LETTER FINAL SIGMA
    chr(963)	=> 'sigma',	# GREEK SMALL LETTER SIGMA
    chr(964)	=> 'tau',	# GREEK SMALL LETTER TAU
    chr(965)	=> 'upsilon',	# GREEK SMALL LETTER UPSILON
    chr(966)	=> 'phi',	# GREEK SMALL LETTER PHI
    chr(967)	=> 'chi',	# GREEK SMALL LETTER CHI
    chr(968)	=> 'psi',	# GREEK SMALL LETTER PSI
    chr(969)	=> 'omega',	# GREEK SMALL LETTER OMEGA
    chr(977)	=> 'thetasym',	# GREEK THETA SYMBOL
    chr(978)	=> 'upsih',	# GREEK UPSILON WITH HOOK SYMBOL
    chr(982)	=> 'piv',	# GREEK PI SYMBOL
    chr(8194)	=> 'ensp',	# EN SPACE
    chr(8195)	=> 'emsp',	# EM SPACE
    chr(8201)	=> 'thinsp',	# THIN SPACE
    chr(8204)	=> 'zwnj',	# ZERO WIDTH NON-JOINER
    chr(8205)	=> 'zwj',	# ZERO WIDTH JOINER
    chr(8206)	=> 'lrm',	# LEFT-TO-RIGHT MARK
    chr(8207)	=> 'rlm',	# RIGHT-TO-LEFT MARK
    chr(8211)	=> 'ndash',	# EN DASH
    chr(8212)	=> 'mdash',	# EM DASH
    chr(8216)	=> 'lsquo',	# LEFT SINGLE QUOTATION MARK
    chr(8217)	=> 'rsquo',	# RIGHT SINGLE QUOTATION MARK
    chr(8218)	=> 'sbquo',	# SINGLE LOW-9 QUOTATION MARK
    chr(8220)	=> 'ldquo',	# LEFT DOUBLE QUOTATION MARK
    chr(8221)	=> 'rdquo',	# RIGHT DOUBLE QUOTATION MARK
    chr(8222)	=> 'bdquo',	# DOUBLE LOW-9 QUOTATION MARK
    chr(8224)	=> 'dagger',	# DAGGER
    chr(8225)	=> 'Dagger',	# DOUBLE DAGGER
    chr(8226)	=> 'bull',	# BULLET
    chr(8230)	=> 'hellip',	# HORIZONTAL ELLIPSIS
    chr(8240)	=> 'permil',	# PER MILLE SIGN
    chr(8242)	=> 'prime',	# PRIME
    chr(8243)	=> 'Prime',	# DOUBLE PRIME
    chr(8249)	=> 'lsaquo',	# SINGLE LEFT-POINTING ANGLE QUOTATION MARK
    chr(8250)	=> 'rsaquo',	# SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
    chr(8254)	=> 'oline',	# OVERLINE
    chr(8260)	=> 'frasl',	# FRACTION SLASH
    chr(8364)	=> 'euro',	# EURO SIGN
    chr(8465)	=> 'image',	# BLACK-LETTER CAPITAL I
    chr(8472)	=> 'weierp',	# WEIERSTRASS ELLIPTIC FUNCTION
    chr(8476)	=> 'real',	# BLACK-LETTER CAPITAL R
    chr(8482)	=> 'trade',	# TRADE MARK SIGN
    chr(8501)	=> 'alefsym',	# ALEF SYMBOL
    chr(8592)	=> 'larr',	# LEFTWARDS ARROW
    chr(8593)	=> 'uarr',	# UPWARDS ARROW
    chr(8594)	=> 'rarr',	# RIGHTWARDS ARROW
    chr(8595)	=> 'darr',	# DOWNWARDS ARROW
    chr(8596)	=> 'harr',	# LEFT RIGHT ARROW
    chr(8629)	=> 'crarr',	# DOWNWARDS ARROW WITH CORNER LEFTWARDS
    chr(8656)	=> 'lArr',	# LEFTWARDS DOUBLE ARROW
    chr(8657)	=> 'uArr',	# UPWARDS DOUBLE ARROW
    chr(8658)	=> 'rArr',	# RIGHTWARDS DOUBLE ARROW
    chr(8659)	=> 'dArr',	# DOWNWARDS DOUBLE ARROW
    chr(8660)	=> 'hArr',	# LEFT RIGHT DOUBLE ARROW
    chr(8704)	=> 'forall',	# FOR ALL
    chr(8706)	=> 'part',	# PARTIAL DIFFERENTIAL
    chr(8707)	=> 'exist',	# THERE EXISTS
    chr(8709)	=> 'empty',	# EMPTY SET
    chr(8711)	=> 'nabla',	# NABLA
    chr(8712)	=> 'isin',	# ELEMENT OF
    chr(8713)	=> 'notin',	# NOT AN ELEMENT OF
    chr(8715)	=> 'ni',	# CONTAINS AS MEMBER
    chr(8719)	=> 'prod',	# N-ARY PRODUCT
    chr(8721)	=> 'sum',	# N-ARY SUMMATION
    chr(8722)	=> 'minus',	# MINUS SIGN
    chr(8727)	=> 'lowast',	# ASTERISK OPERATOR
    chr(8730)	=> 'radic',	# SQUARE ROOT
    chr(8733)	=> 'prop',	# PROPORTIONAL TO
    chr(8734)	=> 'infin',	# INFINITY
    chr(8736)	=> 'ang',	# ANGLE
    chr(8743)	=> 'and',	# LOGICAL AND
    chr(8744)	=> 'or',	# LOGICAL OR
    chr(8745)	=> 'cap',	# INTERSECTION
    chr(8746)	=> 'cup',	# UNION
    chr(8747)	=> 'int',	# INTEGRAL
    chr(8756)	=> 'there4',	# THEREFORE
    chr(8764)	=> 'sim',	# TILDE OPERATOR
    chr(8773)	=> 'cong',	# APPROXIMATELY EQUAL TO
    chr(8776)	=> 'asymp',	# ALMOST EQUAL TO
    chr(8800)	=> 'ne',	# NOT EQUAL TO
    chr(8801)	=> 'equiv',	# IDENTICAL TO
    chr(8804)	=> 'le',	# LESS-THAN OR EQUAL TO
    chr(8805)	=> 'ge',	# GREATER-THAN OR EQUAL TO
    chr(8834)	=> 'sub',	# SUBSET OF
    chr(8835)	=> 'sup',	# SUPERSET OF
    chr(8836)	=> 'nsub',	# NOT A SUBSET OF
    chr(8838)	=> 'sube',	# SUBSET OF OR EQUAL TO
    chr(8839)	=> 'supe',	# SUPERSET OF OR EQUAL TO
    chr(8853)	=> 'oplus',	# CIRCLED PLUS
    chr(8855)	=> 'otimes',	# CIRCLED TIMES
    chr(8869)	=> 'perp',	# UP TACK
    chr(8901)	=> 'sdot',	# DOT OPERATOR
    chr(8968)	=> 'lceil',	# LEFT CEILING
    chr(8969)	=> 'rceil',	# RIGHT CEILING
    chr(8970)	=> 'lfloor',	# LEFT FLOOR
    chr(8971)	=> 'rfloor',	# RIGHT FLOOR
    chr(9001)	=> 'lang',	# LEFT-POINTING ANGLE BRACKET
    chr(9002)	=> 'rang',	# RIGHT-POINTING ANGLE BRACKET
    chr(9674)	=> 'loz',	# LOZENGE
    chr(9824)	=> 'spades',	# BLACK SPADE SUIT
    chr(9827)	=> 'clubs',	# BLACK CLUB SUIT
    chr(9829)	=> 'hearts',	# BLACK HEART SUIT
    chr(9830)	=> 'diams',	# BLACK DIAMOND SUIT
);

# Fill in missing entities
for (0 .. 255) {
    next if exists $char2entity{chr($_)};
    $char2entity{chr($_)} = "#$_";
}

# Wrap all in '&' and ';'.
foreach my $c ( keys(%char2entity) ) {
    $char2entity{$c} = "&" . $char2entity{$c} . ";";
}

sub encode_entities {
    return undef unless defined $_[0];
    my $ref;

    if (defined wantarray) {
	my $x = $_[0];
	$ref = \$x;     # copy

    } else {
	$ref = \$_[0];  # modify in-place
    }

    # "\ " -> chr(160) (-> "&nbsp;")
    $$ref =~ s/\\ /chr(160)/ge;

    # \& \< \> -> &amp; &lt; &gt;
    $$ref =~ s/\\([<&>])/$char2entity{$1} || num_entity($1)/ge;

    # Encode control chars, high bit chars.
    $$ref =~ s/([^\n\r\t !\#\$&%\(-;<=>?-~'"])/$char2entity{$1} || num_entity($1)/ge;

    # Special case: " & ", ampersand surrounded by whitespace -> " &amp; "
    $$ref =~ s/\s+(&)\s+/" " . ($char2entity{$1} || num_entity($1)) . " "/ge;

    $$ref;
}

sub num_entity {
    sprintf "&#x%X;", ord($_[0]);
}

sub encode_entities_numeric {
    local %char2entity;
    return &encode_entities;
}



# =========================================================================
# Main Loop
# =========================================================================

unless ($overwrite) {
    $outdir = $destination unless defined($outdir);
    unless (-d "$outdir") {
	$outfile = basename("$outdir");
	$outdir  = dirname("$outdir");
    }
}

FILE : foreach my $file ( @ARGV ) {
    # ---------------------------------------------------------------------
    # Read the file and determine its file type

    print "< $file\n" if $verbose;
    open(my $IN, '<', $file) or die "Cannot open '$file': $!, stopped";

    my $filename = basename($file, "");
    my $type = "default";       # not yet known whether this is a special file.
    $outdir = dirname($file) if $overwrite;

    unless ($file eq "-") {
        # Determine the file type.
        if ($file =~ m/\.(\w+)$/) {
            $type = $1;
            unless (defined($file_table{$type})) {
                print STDERR "Error: Undefined file type: $type ($filename)\n";
                $type = "default";
            }

            if (defined($file_table{$type}{"out"}) && !$overwrite) {
                # Through the file table entry "out", a new filename
                # extension can be specified, e.g. test.xrc => test.html
                $filename = $` . "." . $file_table{$type}{"out"};
            }
        }
    }

    if (defined($outfile)) {
	# The use gave us a specific file name.
        $file = catfile( $outdir, $outfile );

    } elsif ($file ne "-") {
        # the result file is to be stored in a different directory.
        $file = catfile( $outdir, $filename ) unless $overwrite;
    }

    my $xmlver = "1.0";  # default XML version is 1.0
    my $out = "";        # the resulting text
    my $wrap = $file_table{$type}{"textwidth"};
    my $isxml = ($type eq "xml");

    if ($verbose) {
        print "\tfile type: $type (" . $file_table{$type}{"info"} . ") \n";
        print "\tcompress : " . (($file_table{$type}{"compress"} > 0) ? "on" : "off") . "\n";
        print "\tnon_ascii: " . (($file_table{$type}{"non_ascii"} > 0) ? "on" : "off") . "\n";
    }

    undef $/;  # no input separator = read entire file at once

    # ---------------------------------------------------------------------
    # File Processing

    LINE : while (<$IN>) {
        next LINE unless $_;

        # -----------------------------------------------------------------
        # pre-process

        # Run the first sub-routine from the project-specific package.
        if (defined(&{"${site_package_name}::pre_process"})) {
            print "- ${site_package_name}::pre_process\n" if $verbose;
            &{"${site_package_name}::pre_process"}($filename, $type);

        } elsif ($verbose) {
            print "? ${site_package_name}::pre_process\n";
        }


        # -----------------------------------------------------------------
        # Initial checks

        my $i;

        # Detect whether it is an XML file.
        if (m/^<(\??)XML([^\?>]*)\g1>/i) {
            $i = $2;
            $xmlver = $1 if ($i =~ m/version="(\d+\.\d+)"/i);
##          $type = "xml";
            $isxml = 1;
        }

        print STDERR "Warning: File uses non-UNIX carriage returns.\n" if (/\r/);
        s/[\r\f\n]/\n/g;    # translate newlines

        s/\n__END__\n.*//s; # remove anything beyond "__END__"


        # -----------------------------------------------------------------
        # process

        # Run the main sub-routine from the project-specific package.
        if (defined (&{"${site_package_name}::process"})) {
            print "- ${site_package_name}::process\n" if $verbose;
            &{"${site_package_name}::process"}($filename, $type);

        } elsif ($verbose) {
            print "? ${site_package_name}::process\n";
        }


        # -----------------------------------------------------------------
        # special keywords: <<longdate>> <<date>> <<file>>

        s/${hxpr_beg}longdate${hxpr_end}/$longdate/ig;
        s/${hxpr_beg}date${hxpr_end}/$date/ig;
        s/${hxpr_beg}file${hxpr_end}/$filename/ig;

        $wrap = 0 if s/${hxpr_beg}nowrap${hxpr_end}//ig;


        # -----------------------------------------------------------------
        # <!DOCTYPE> declaration

        # this should be one of: <<doctype strict>>,
        # <<doctype transitional>>, or <<doctype frameset>>
        my $page = "";
        if ($type eq "xml" || $isxml) {

            # XHTML, HTML in XML format.
            if ($xmlver eq "1.0") {
                # XHTML 1.0 declaration
                if (s|${hxpr_beg}doctype\s+(\S+?)${hxpr_end}|<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 \u$1//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-\L$1\E.dtd">|i)
                { $page = $1; }
            } else {
                # XHTML 1.1 (or above?) declaration
                $i = $xmlver;
                $i =~ s/\.//g;
                s|${hxpr_beg}doctype\s+\S+?${hxpr_end}|<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML $xmlver//EN" "http://www.w3.org/TR/xhtml$i/DTD/xhtml$i.dtd">|i;
            }

            s|<html>|<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">|i;
            s|<html\s+(\S+)>|<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="$1" lang="$1">|i;
            s|"text/html"|"application/xml"|g;
            s!<(br|hr)([^>]*)>!<\L$1\E$2/>!ig;      # single tags must be closed
            s!<(link|meta)([^>]+[^>/])>!<\L$1\E$2/>!ig;  # single tags must be closed
            s|<(img [^>]+[^>/])>|<$1/>|ig;           # ditto for <img />

        } else {
            # standard HTML 4.01 declaration
            if (m|${hxpr_beg}doctype\s+(\S+?)${hxpr_end}|) {
                my $mode = $page = "\L$1\E";
                $page = "loose"  if ($page eq "transitional");
                $mode = ""  if ($mode eq "strict");
                $mode = " \u$mode"  if $mode;

                s|${hxpr_beg}doctype\s+(\S+?)${hxpr_end}|<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01$mode//EN" "http://www.w3.org/TR/html4/\L$page\E.dtd">|g;
            }
        }


        # -----------------------------------------------------------------
        # Convert Non-ASCII characters

        if ($file_table{$type}{"non_ascii"} > 0) {
            # Exchange special characters by their HTML code
            # NB. This section is incomplete - only common chars are handled.

            print "- Converting umlauts\n" if $verbose;

            # Canonical decomposition followed by canonical composition.
            # This is to combine wide Unicode code sequences where possible.
            $_ = NFC($_);

            if ($type eq "xml" || $isxml) {
                # In XML, most name symbols are not automatically defined.
                # To avoid having to do just that, we insert their number
                # equivalent instead.
		&encode_entities_numeric($_);

	    } else {
		&encode_entities($_);
	    }
        }


        # -----------------------------------------------------------------
        # Comments Removal (always)

        # We cater for three types of comments that will be removed from
        # the resulting HTML file:
        # - comments after a "\s#" to the end of a line
        #   ( there must be a whitespace before it to catch href="#top" ).
        # - <!-- HTML style comments all in one line -->
        # - HTML style comments over several lines
        # exceptions:
        # - embedded JavaScript must remain preserved.
        # - style sheets (CSS) don't use # comments, but /* comment */

        if ($type eq "css" || $type eq "php" || m|<\?php|) {
            # // comments
            while (s!(?:^|\s+)//.*?\n!\n!g) { };  # comments after ' //'

            # /* comments */
            while (m!(?:^|\s+)/\*!) {
                s|/\*[^\n]*?\*/||g;    # remove single-line comments
                s|(/\*.*?)\n|$1|;      # otherwise concat lines
            }
        }

        if ($type ne "css") {
            # despite /g this needs to be run several times:
            while (s/(?:^|\s+)#.*?\n/\n/g) { };      # comments after ' #'
            s/\\#/#/g;                               # but not '\#'
        }

        # Mask JavaScripts to prevent it from being removed as comments
        if (m|</script>|i) {
            s|(script">)\s*<!--(\s)|$1<!==$2|ig;        # <!--  ->  <!==
            s|(//\s*)-->\s*(</script>)|$1==>$2|ig;      # ==>   ->  ==>
            $wrap = 0;
        }

        # Mask server-side include (SSI) comments from being removed
        # They must conform to the style: <!--\#cmd key="code" --> .
        s/<!--(#(?:set)\s+\S+=\"\S+\"\s+\S+=\"\S+\")\s+-->/<!==$1 ==>/g;
        s/<!--(#(?:elif|if)\s+\S+='[^']+')\s+-->/<!==$1 ==>/g;
        s/<!--(#(?:config|echo|elif|exec|if|include)\s+\S+=\"\S+\")\s+-->/<!==$1 ==>/g;
        s/<!--(#(?:else|endif))\s+-->/<!==$1 ==>/g;

        # Ordinary <!-- HTML comments --> in one line.
        s/\n[ \t]*<!--.*?-->[ \t]*\n/\n/g;   # remove entire line
        s/<!--.*?-->//g;                     # or else just the comment

        # HTML-style multi-line comments, with <!-- and --> in separate lines
        while (m/<!--/) {
            s/<!--[^\n]*?-->//g;    # remove single-line comments
            s/(<!--.*)\n/$1/;       # otherwise concat lines
        }

        # Undo the SSI-masking.
        s/<!==(#(?:set)\s+\S*=\"\S+\"\s+\S*=\"\S+\" )==>/<!--$1-->/g;
        s/<!==(#(?:config|echo|elif|exec|if|include)\s+\S*=\"\S+\" )==>/<!--$1-->/g;
        s/<!==(#(?:elif|if)\s+\S+='[^']+' )==>/<!--$1-->/g;
        s/<!==(#(?:else|endif) )==>/<!--$1-->/g;


        # -----------------------------------------------------------------
        # Additional compression

        if ($file_table{$type}{"compress"} > 1) {
            # This may not be recommended (for instance with style sheets).
##          s|<(/?)address((\s[^>]*)?)>|<$1i$2>|ig;   # <address> -> <i>
##          s|<(/?)code((\s[^>]*)?)>|<$1tt$2>|ig;     # <code>    -> <tt>
            s|<(/?)strong((\s[^>]*)?)>|<$1b$2>|ig;    # <strong>  -> <b>
            s|<(/?)em((\s[^>]*)?)>|<$1i$2>|ig;        # <em>      -> <i>
        }


        # -----------------------------------------------------------------
        # Whitespace removal

        if ($file_table{$type}{"compress"} > 0) {
            # We remove pretty much all whitespace caracters except in
            # <pre> sections.

            print "- Whitespace removal\n" if $verbose;

            while (m|<pre>.*?\s.*?</pre>|s) {
                s|(<pre>\S*?) (.*</pre>)|$1<:s:>$2|sg;  # protect spaces
                s|(<pre>\S*?)\t(.*</pre>)|$1<:t:>$2|sg; # protect tabs
                s|(<pre>\S*?)\n(.*</pre>)|$1<:n:>$2|sg; # protect newlines
                $wrap = 0;
            }

            s/\s\s+/ /g;    # no multiple white spaces.
            s/^\s+//;       # no spaces at the beginning of the file.
            s/\s+$//;       # no spaces before EOF.
            s/>\s+</></g;   # no spaces between HTML tags
            s|\s+</|</|g;   # no spaces before closing HTML tags

            if ($type eq "css") {
                # cascading style sheets
                s/\s+({|}|:|;|,)/$1/g;  # no spaces before punctuation marks
                s/({|}|:|;|,)\s+/$1/g;  # or after them
                s/;}/}/g;               # no ; before } required

            } else {
                # No spaces around certain HTML tags.
                s!\s*(</?(blockquote|br|center|div|font|li|p|table|td|th|tr|ul|wbr))(\s+[^>]+>|>)\s*!$1$3!ig;

                # Delete not required HTML code (not XML).
                s!</(?:li|p|dd|dt)>!!ig unless $type;
            }
        }


        # -----------------------------------------------------------------
        # And at the top we shall add a copyright string.

        if ($add_banner) {
            if ($type eq "css") {
                s|^|/* $copyright */\n\n|;

            } else {
                s/(<html[^>]*>)/$1\n\n<!-- $copyright -->\n\n/i;
            }
        }


        # -----------------------------------------------------------------
        # Recover JavaScript formatting

        if (m|</script>|i) {
            s/(\)\;)\s*/$1\n/g;     # );\n

            # <!== ==>  ->  <!-- -->
            if ($type eq "xml" || $isxml) {
                s|(script">)\s*<!==\s|$1\n<!--\n|ig;    # script">\n<![CDATA[\n
                s|(//\s*)==>(</script>)|$1-->\n$2|ig;   # // ]]>\n</script>

            } else {
                s|(script">)\s*<!==\s|$1\n<!--\n|ig;    # script">\n<!--\n
                s|(//\s*)==>(</script>)|$1-->\n$2|ig;   # // -->\n</script>
            }
        }


        # -----------------------------------------------------------------
        # Text Wrapping

        if ($wrap > 0) {
            # We only wrap lines in the absence of JavaScripts as it has
            # proven to corrupt the scripts.

            print "- Wrapping: $wrap\n" if $verbose;

            # Set the column width (defaults to 76).
            $Text::Wrap::columns = $wrap;

            # Allow overflow when a line cannot be broken.
            # Otherwise "wrap" may die on us.
            $Text::Wrap::huge    = "overflow";

            # Add suggested break points: in between <html><tags>.
            s|><|> <|g;

            $_ = wrap("","",$_);

            # Remove unused break points.
            s|> <|><|g;

            # Known corrections.
            s|(</*)\n|\n$1|g;           # <\n  or  </\n
            s|\n>|>\n|g;                # \n>
        }


        # -----------------------------------------------------------------
        # Cleanup

        if ($file_table{$type}{"compress"} > 0) {
            # restore spaces, tabs, and newlines in <pre>
            s|<:s:>| |g;   s|<:t:>|\t|g;   s|<:n:>|\n|g;
        }

        # Check if any undetected <:macros:> are left
	my %tokens;
        foreach my $macro ( m|(${hxpr_beg}.*?${hxpr_end})|i ) {
	    $tokens{"$macro"} = 1;
	}

	unless (%tokens) {
	    # Check if <:begin or end:> tokens exist
	    foreach my $macro ( m|(${hxpr_beg}\S*)|i ) { $tokens{"$macro"} = 1; }
	    foreach my $macro ( m|(\S*${hxpr_end})|i ) { $tokens{"$macro"} = 1; }
	}

	if (%tokens) {
            print STDERR "Error: Detected unexpanded tokens: " . join(", ", keys(%tokens)) . ".\n";
        }


        # -----------------------------------------------------------------
        # Check embedded links

        if ($verbose || $href_check) {
            my( $href, $anchor, $tmp, %href_table );
            $tmp = "/tmp/htmlXPress-$$";
            %href_table = ();

            print "- Links:\n" if $verbose;

            while (m|href="([^"]+)"|gc) {
                unless ($href_table{$href=$1}) {
                    print "\t$href\n";
                    $href_table{$href} = 1;
                    if ($href_check) {
                        if ($href =~ m'^(?:http|ftp)://') {
                            # external link - get the page header (then delete it)
                            system("$curl_exec --head --silent -o $tmp $href");
                            system("rm $tmp");
                            print STDERR "Error: Broken link to $href (" . ($?>>8) . ")\n"
                                if (( $? >> 8 ) > 0);

                        } else {
                            $anchor = ($href =~ s/(\S+)#(\S+)/$1/) ? $2 : "";
                            print STDERR "Warning: Check anchor \"$anchor\" in \"$href\".\n"
                                if ($anchor && $anchor !~ /^[a-z]{3}\b/);

                            print STDERR "Error: Broken link to \"$href\".\n"
                                unless (-e catfile($outdir, $href));
                        }
                    }
                }
            }
        }

        if (defined (&{"${site_package_name}::post_process"})) {
            print "- ${site_package_name}::post_process\n" if $verbose;
            &{"${site_package_name}::post_process"}($filename, $type);

        } elsif ($verbose) {
            print "? ${site_package_name}::post_process\n";
        }

        $out .= "$_\n";
    }

    close $IN;


    # =====================================================================
    # Write out the result.
    # =====================================================================

    if ($verbose) {
        print "> $file";
        print " (overwriting)" if -e $file;
        print "\n";
    }

    open(my $OUT, ">" . $file ) or die "Cannot open '$file': $!, stopped";
    print $OUT $out;
    close $OUT;


    # ---------------------------------------------------------------------
    # Macintosh creator codes, using SetFile executable:

    if ($file_table{$type}{"creator"} ne "" && -x $set_file_exec) {
        system "$set_file_exec -c " . $file_table{$type}{"creator"} . " -t TEXT $file";
    }


    # ---------------------------------------------------------------------
    # Lint-checking

    if ($lint && ($type eq "xml" || $isxml)) {
        system("$xml_lint_command $file");
    }
}


__END__

# =========================================================================
# Command-line help
# =========================================================================

=head1 NAME

htmlXPress - to compress and format HTML files

=head1 SYNOPSIS

htmlXPress [options] [-|file...]

  Options:
    -help|usage A brief help page (use twice for more)
    -href_check Check all hyperlinks for validity (default off)
    -lint       Post-process lint-checking (XML only)
    -inplace    Allow over-writing same file
    -verbose    Shows progress messages
    -debug      Shows debug messages

=head1 Options

=over 8

=item B<-help>|B<-usage>

Shows this help page on the usage of htmlXPress. More details are shown
if this option is used twice.

=item B<-inplace>|B<-overwrite>

Allows overwriting the input file.

=item B<-href_check>

When given checks all hyperlinks in order to find broken links.
This uses B<curl> for external links (requires a net connection).
Remember that N<-verbose> will list links.

=item B<-lint>

Runs the resulting file through B<xmllint> (XML only).

=item B<-out> dir_or_file_name

Writes the result to the given file (when a file name is given),
or to the given directory, with the original (or mapped) file
name. This takes preference to the \$destination variable.

=item B<-verbose>

Prints selected progress messages.

=item B<-debug>

Prints many more debug-related messages.

=back

=head1 DESCRIPTION

B<htmlXPress> compresses and formats HTML files (or STDIN if you pass
"-" as the file name). The compression is through the removal of
unnecessary comments and white-space characters. The appearance in the
web browser is not changed. User-defined macros can be defined in a
site-specific package file.

=head1 AUTHOR

Copyright (c) 2000, tredje design - Eric Roller.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut
