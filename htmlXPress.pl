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

my $version = "4.0";

# Version History
# ===============
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

use File::Basename;         # basename, dirname
use File::Spec::Functions;  # catdir, catfile, curdir
use Getopt::Long;           # GetOptions
use Pod::Usage;             # pod2usage
use Text::Wrap;             # wrap


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

our $destination = "";


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
# Load configuration file
# -------------------------------------------------------------------------
# The user may like to change the above variables (as described above).

do "$ENV{HOME}/.htmlxpressrc";


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

    eval "use $site_package_name";

    # Activate site-specific settings.
    foreach my $varname ( "add_banner", "curl_exec", "date_format",
                "default_creator", "destination", "set_file_exec",
                "site_package_name", "xml_lint_command" ) {
        $$varname = ${"${site_package_name}::$varname"}
                if (defined(${"${site_package_name}::$varname"}));
    }
}


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

unless ($overwrite) {
    $outdir = $destination unless defined($outdir);
    die "Output directory not found: '$outdir', stopped" unless (-d "$outdir");
}

print "$prog, starting on $longdate\n" if $verbose;

if ($debug) {
    my $exec_path = (split /\s+/, $xml_lint_command)[0];
    print STDERR "Error: No executable at \$xml_lint_command: $xml_lint_command\n" if (! -x $exec_path);
    
    # Debug settings
    print "Variables:\n";
    foreach my $varname ( "add_banner", "curl_exec", "date_format",
                "default_creator", "destination", "set_file_exec",
                "site_package_name", "xml_lint_command" ) {
        print "\t\$$varname = \"$$varname\";\n";
    }
}


# -------------------------------------------------------------------------
# Import site-specifict data
# -------------------------------------------------------------------------
# This is where we merge the site's file table with our gobal one.

$file_table{"default"}{"creator"} = $default_creator;

if ($site_package_name ne "")
{
    # Site-specific file_table entries take precedence.
    # New settings are appended.
    
    if (%{"${site_package_name}::file_table"})
    {
        print "- Importing site-specific data\n" if $verbose;

        foreach my $type ( keys(%{"${site_package_name}::file_table"}) )
        {
            foreach my $code ( keys(%{"${site_package_name}::file_table{$type}"}) )
            {
                $file_table{$type}{$code} = ${"${site_package_name}::file_table{$type}{$code}"};
                print "\t$type.$code => $file_table{$type}{$code}\n" if $debug;
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

do
{
    $done = 1;

    foreach my $type ( keys(%file_table) )
    {
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



# =========================================================================
# Main Loop
# =========================================================================

FILE : foreach my $file ( @ARGV )
{
    # ---------------------------------------------------------------------
    # Read the file and determine its file type

    print "< $file\n" if $verbose;
    open(IN, $file) or die "Cannot open '$file': $!, stopped";
    
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

    LINE : while (<IN>)
    {
        next LINE unless $_;
        
        # -----------------------------------------------------------------
        # pre-process

        # Run the first sub-routine from the project-specific package.
        if (defined(&{"${site_package_name}::pre_process"})) {
            print "- ${site_package_name}::pre_process\n" if $verbose;
            &{"${site_package_name}::pre_process"}($filename, $type);
        }


        # -----------------------------------------------------------------
        # Initial checks

        my $i;
        
        # Detect whether it is an XML file.
        if (m/^<\??XML([^\?>]*)\??>/i) {
            $i = $1;
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
        }


        # -----------------------------------------------------------------
        # special keywords

        s/<<longdate>>/$longdate/ig;
        s/<<date>>/$date/ig;
        s/<<file>>/$filename/ig;
        
        # A urlfile is "abc.html", not "abc.html.sv".
        $filename =~ s/(\.\S+)\.\w\w/$1/;
        s/<<urlfile>>/$filename/ig;
        
        $wrap = 0 if s/<<nowrap>>//ig;


        # -----------------------------------------------------------------
        # <!DOCTYPE> declaration

        # this should be one of: <<doctype strict>>,
        # <<doctype transitional>>, or <<doctype frameset>>
        my $page = "";
        if ($type eq "xml" || $isxml) {

            # XHTML, HTML in XML format.
            if ($xmlver eq "1.0") {
                # XHTML 1.0 declaration
                if (s|<<doctype\s+(\S+)>>|<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 \u$1//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-\L$1\E.dtd">|i)
                { $page = $1; }
            } else {
                # XHTML 1.1 (or above?) declaration
                $i = $xmlver;
                $i =~ s/\.//g;
                s|<<doctype\s+\S+>>|<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML $xmlver//EN" "http://www.w3.org/TR/xhtml$i/DTD/xhtml$i.dtd">|i;
            }

            s|<html>|<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">|i;
            s|<html\s+(\S+)>|<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="$1" lang="$1">|i;
            s|"text/html"|"application/xml"|g;
            s!<(br|hr)([^>]*)>!<\L$1\E$2/>!ig;      # single tags must be closed
            s!<(link|meta)([^>]+[^>/])>!<\L$1\E$2/>!ig;  # single tags must be closed
            s|<(img [^>]+[^>/])>|<$1/>|ig;           # ditto for <img />

        } else {

            # standard HTML 4.01 declaration
            if (m|<<doctype\s+(\S+)>>|) {
                my $mode = $page = "\L$1\E";
                $page = "loose"  if ($page eq "transitional");
                $mode = ""  if ($mode eq "strict");
                $mode = " \u$mode"  if $mode;

                s|<<doctype\s+(\S+)>>|<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01$mode//EN" "http://www.w3.org/TR/html4/\L$page\E.dtd">|g;
            }
        }


        # -----------------------------------------------------------------
        # Convert Non-ASCII characters

        if ($file_table{$type}{"non_ascii"} > 0)
        {
            # Exchange special characters by their HTML code
            # NB. This section is incomplete - only common chars are handled.
            
            print "- Converting umlauts\n" if $verbose;

            s/ä/&auml;/g;
            s/à/&agrave;/g;
            s/á/&aacute;/g;
            s/â/&acirc;/g;
            s/ã/&atilde;/g;
            s/å/&aring;/g;
            s/æ/&aelig;/g;
            s/ç/&ccedil;/g;
            s/ë/&euml;/g;
            s/è/&egrave;/g;
            s/é/&eacute;/g;
            s/ê/&ecirc;/g;
            s/ð/&eth;/g;
            s/ï/&iuml;/g;
            s/ì/&igrave;/g;
            s/í/&iacute;/g;
            s/î/&icirc;/g;
            s/ñ/&ntilde;/g;
            s/ö/&ouml;/g;
            s/ò/&ograve;/g;
            s/ó/&oacute;/g;
            s/ô/&ocirc;/g;
            s/õ/&otilde;/g;
            s/ø/&oslash;/g;
            s/√ü/&szlig;/g;
            s/þ/&thorn;/g;
            s/ü/&uuml;/g;
            s/ù/&ugrave;/g;
            s/ú/&uacute;/g;
            s/û/&ucirc;/g;
            s/ÿ/&yuml;/g;
            s/ý/&yacute;/g;

            s/Ä/&Auml;/g;
            s/À/&Agrave;/g;
            s/Á/&Aacute;/g;
            s/Â/&Acirc;/g;
            s/Ã/&Atilde;/g;
            s/Å/&Aring;/g;
            s/Æ/&AElig;/g;
            s/Ç/&Ccedil;/g;
            s/Ë/&Euml;/g;
            s/È/&Egrave;/g;
            s/É/&Eacute;/g;
            s/Ê/&Ecirc;/g;
            s/Ð/&ETH;/g;
            s/Ï/&Iuml;/g;
            s/Ì/&Igrave;/g;
            s/Í/&Iacute;/g;
            s/Î/&Icirc;/g;
            s/Ñ/&Ntilde;/g;
            s/Ö/&Ouml;/g;
            s/Ò/&Ograve;/g;
            s/Ó/&Oacute;/g;
            s/Ô/&Ocirc;/g;
            s/Õ/&Otilde;/g;
            s/Ø/&Oslash;/g;
            s/Þ/&THORN;/g;
            s/Ü/&Uuml;/g;
            s/Ù/&Ugrave;/g;
            s/Ú/&Uacute;/g;
            s/Û/&Ucirc;/g;
            s/Ÿ/&Yuml;/g;
            s/Ý/&Yacute;/g;

            s/¡/&iexcl;/g;
            s/¿/&iqiest;/g;
            s/€/&euro;/g;
            s/¢/&cent;/g;
            s/£/&pound;/g;
            s/¥/&yen;/g;
            s/©/&copy;/g;
            s/®/&reg;/g;
            s/°/&deg;/g;
            s/¬/&not;/g;
            s/¨/&uml;/g;
            s/´/&acute;/g;
            s/`/&grave;/g;  
            s/ª/&ordf;/g;
            s/º/&ordm;/g;
            s/±/&plusmn;/g;
            #//&divide;/g;
            s/§/&para;/g;
            s/§/&sect;/g;
            s/µ/&micro;/g;
            s/•/&middot;/g;
            s/¬Ø/&macr;/g;
            s/¸/&cedil;/g;

            s/\\ /&nbsp;/g;      # \<SPC>
            s/\\&/&amp;/g;       # \&
            s/\\\\</\\&lt;/g;    # \\< ->  \&lt;
            s/\\</&lt;/g;        # \<  ->  &lt;
            s/\\\\>/\\&gt;/g;    # \\> ->  \&gt;
            s/\\>/&gt;/g;        # \>  ->  &gt;

            s//&#147;/g;       # opt-[
            s//&#148;/g;       # opt-shft-[
            #s/'/&#146;/g;
            s//&#151;/g;
            s/…/&#133;/g;
            
            if ($type eq "xml" || $isxml)
            {
                # In XML, these name symbols are not automatically defined.
                # To avoid having to do just that, we insert their number
                # equivalent instead.

                # The following list is certainly not complete.
                # Feel free to submit further symbols.
                s/&euro;/&#128;/g;
                s/&nbsp;/&#160;/g;
                s/&iexcl;/&#161;/g;
                s/&cent;/&#162;/g;
                s/&pound;/&#163;/g;
                s/&curren;/&#164;/g;
                s/&yen;/&#165;/g;
                s/&brvbar;/&#166;/g;
                s/&sect;/&#167;/g;
                s/&uml;/&#168;/g;
                s/&copy;/&#169;/g;
                s/&ordf;/&#170;/g;
                s/&laquo;/&#171;/g;
                s/&not;/&#172;/g;
                s/&shy;/&#173;/g;
                s/&reg;/&#174;/g;
                s/&macr;/&#175;/g;
                s/&deg;/&#176;/g;
                s/&plusmn;/&#177;/g;
                s/&sup2;/&#178;/g;
                s/&sup3;/&#179;/g;
                s/&acute;/&#180;/g;
                s/&micro;/&#181;/g;
                s/&para;/&#182;/g;
                s/&middot;/&#183;/g;
                s/&cedil;/&#184;/g;
                s/&sup1;/&#185;/g;
                s/&ordm;/&#186;/g;
                s/&raquo;/&#187;/g;
                s/&frac14;/&#188;/g;
                s/&frac12;/&#189;/g;
                s/&frac34;/&#190;/g;
                s/&iquest;/&#191;/g;
                s/&Agrave;/&#192;/g;
                s/&Aacute;/&#193;/g;
                s/&Acirc;/&#194;/g;
                s/&Atilde;/&#195;/g;
                s/&Auml;/&#196;/g;
                s/&Aring;/&#197;/g;
                s/&AElig;/&#198;/g;
                s/&Ccedil;/&#199;/g;
                s/&Egrave;/&#200;/g;
                s/&Eacute;/&#201;/g;
                s/&Ecirc;/&#202;/g;
                s/&Euml;/&#203;/g;
                s/&Igrave;/&#204;/g;
                s/&Iacute;/&#205;/g;
                s/&Icirc;/&#206;/g;
                s/&Iuml;/&#207;/g;
                s/&ETH;/&#208;/g;
                s/&Ntilde;/&#209;/g;
                s/&Ograve;/&#210;/g;
                s/&Oacute;/&#211;/g;
                s/&Ocirc;/&#212;/g;
                s/&Otilde;/&#213;/g;
                s/&Ouml;/&#214;/g;
                s/&times;/&#215;/g;
                s/&Oslash;/&#216;/g;
                s/&Ugrave;/&#217;/g;
                s/&Uacute;/&#218;/g;
                s/&Ucirc;/&#219;/g;
                s/&Uuml;/&#220;/g;
                s/&Yacute;/&#221;/g;
                s/&THORN;/&#222;/g;
                s/&szlig;/&#223;/g;
                s/&agrave;/&#224;/g;
                s/&aacute;/&#225;/g;
                s/&acirc;/&#226;/g;
                s/&atilde;/&#227;/g;
                s/&auml;/&#228;/g;
                s/&aring;/&#229;/g;
                s/&aelig;/&#230;/g;
                s/&ccedil;/&#231;/g;
                s/&egrave;/&#232;/g;
                s/&eacute;/&#233;/g;
                s/&ecirc;/&#234;/g;
                s/&euml;/&#235;/g;
                s/&igrave;/&#236;/g;
                s/&iacute;/&#237;/g;
                s/&icirc;/&#238;/g;
                s/&iuml;/&#239;/g;
                s/&eth;/&#240;/g;
                s/&ntilde;/&#241;/g;
                s/&ograve;/&#242;/g;
                s/&oacute;/&#243;/g;
                s/&ocirc;/&#244;/g;
                s/&otilde;/&#245;/g;
                s/&ouml;/&#246;/g;
                s/&divide;/&#247;/g;
                s/&oslash;/&#248;/g;
                s/&ugrave;/&#249;/g;
                s/&uacute;/&#250;/g;
                s/&ucirc;/&#251;/g;
                s/&uuml;/&#252;/g;
                s/&yacute;/&#253;/g;
                s/&thorn;/&#254;/g;
                s/&yuml;/&#255;/g;
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
            while (m!(?:^|\s+)/\*!)
            {
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

        if ($file_table{$type}{"compress"} > 1)
        {
            # This may not be recommended (for instance with style sheets).
##          s|<(/?)address((\s[^>]*)?)>|<$1i$2>|ig;   # <address> -> <i>
##          s|<(/?)code((\s[^>]*)?)>|<$1tt$2>|ig;     # <code>    -> <tt>
            s|<(/?)strong((\s[^>]*)?)>|<$1b$2>|ig;    # <strong>  -> <b>
            s|<(/?)em((\s[^>]*)?)>|<$1i$2>|ig;        # <em>      -> <i>
        }


        # -----------------------------------------------------------------
        # Whitespace removal

        if ($file_table{$type}{"compress"} > 0)
        {
            # We remove pretty much all whitespace caracters except in
            # <pre> sections.
            
            print "- Whitespace removal\n" if $verbose;

            while (m|<pre>.*?\s.*?</pre>|s) {
                s|(<pre>\S*?) (.*</pre>)|$1<<s>>$2|sg;  # protect spaces
                s|(<pre>\S*?)\t(.*</pre>)|$1<<t>>$2|sg; # protect tabs
                s|(<pre>\S*?)\n(.*</pre>)|$1<<n>>$2|sg; # protect newlines
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

        if ($wrap > 0)
        {
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
            s|<<s>>| |g;   s|<<t>>|\t|g;   s|<<n>>|\n|g;
        }

        # check if any undetected macros are left
        if (m|<<([^>]+)>>|i)  {
            print STDERR "Error: Token <<$1>> was not recognised.\n";
        }


        # -----------------------------------------------------------------
        # Check embedded links

        if ($verbose || $href_check)
        {
            my( $href, $anchor, $tmp, %href_table );
            $tmp = "/tmp/htmlXPress-$$";
            %href_table = ();

            print "- Links:\n" if $verbose;

            while (m|href="([^"]+)"|gc)
            {
                unless ($href_table{$href=$1})
                {
                    print "\t$href\n";
                    $href_table{$href} = 1;
                    if ($href_check)
                    {
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
        }

        $out .= "$_\n";
    }

    close IN;


    # =====================================================================
    # Write out the result.
    # =====================================================================

    if ($verbose) {
        print "> $file";
        print " (overwriting)" if -e $file;
        print "\n";
    }
    open(OUT, ">" . $file ) or die "Cannot open '$file': $!, stopped";
    print OUT $out;
    close OUT;


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

=item B<-out> dir_name

Writes the resulting files into the dir_name folder. This takes
preference to the \$destination variable.

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
