# =========================================================================
# site.pm
#
#       Site-specific configuration file
#
# OVERVIEW
#       This file contains additional macros and formatting rules for pages
#       that are processed with htmlXPress.
# =========================================================================

package site;  # assumes site.pm

use strict;
use warnings;

BEGIN {
   # set the version for version checking
   our $VERSION     = 1.00;
}


# -------------------------------------------------------------------------
# add_banner
#
# A boolean as to whether to include a hmtlXPress version banner in the
# output file. This can also be changed on the command-line using -banner
# or -nobanner.

## our $add_banner = 1;


# -------------------------------------------------------------------------
# curl_exec
#
# Contains the path to the curl executable. This is used to check links.
# We will call it using options: --head --silent -o tmp_file "href"

## our $curl_exec = "/usr/bin/curl";


# -------------------------------------------------------------------------
# date_format
#
# The date-format options for POSIX::strftime.
# By default, we shall use the (sortable) ISO-8601 notation: YYYY-MM-DD.

## our $date_format = "%Y-%m-%d";


# -------------------------------------------------------------------------
# default_creator
#
# The default Macintosh file creator code applied to the written files.
# Example:  "R*ch" for BBEdit, or "!Rch" for TextWrangler.

## our $default_creator = "";


# -------------------------------------------------------------------------
# destination
#
# The default output directory, unless given at the command line using the
# -out argument.

## our $destination = "/Library/Web Pages/";	# absolute path
our $destination = "results";			# relative to current directory


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

## our %file_table = (
## 
##     # HTML, compress, wrap lines to 80 characters.
##     html => {
##         info => "Hypert-text markup langage",
##         compress => 2,
##         non_ascii => 1,
##         textwidth => 80,
##     },
## 
## );


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

## our $set_file_exec = "/usr/bin/SetFile";


# -------------------------------------------------------------------------
# xml_lint_command
#
# Contains the path to the xmllint executable, if present, and any options
# that should be used with it.

## our $xml_lint_command = "/usr/bin/xmllint -noout";



# =========================================================================
# pre_process()
# =========================================================================
#
# Optional pre-processing

## sub pre_process($$)
## {
##     my ( $filename, $type ) = @_;
## }



# =========================================================================
# process()
# =========================================================================
#
# The main job is done here.
#
# This is where your site-specific code processing should be done.

sub process($$)
{
    my ( $filename, $type ) = @_;

    # Header section
    # --------------
    # <!DOCTYPE html>
    # <html lang="en">
    # <<head "Page Title in Quotes">>
    #     <meta content=other>
    #     ...
    # <</head>>
    #     ...
    
    if ( $type ne "css" )
    {
	my @date = localtime;
	my $year = 1900 + $date[5];
	
	s|<<head\s+"([^"]+)">>|<head><<meta>><title>$1</title>|;
	s|<</head>>|<<stylesheet example>></head><<body>>|;
	s|<<meta>>|<meta http-equiv="content-type" content="text/html"><meta name="author" content="<<author>>"><meta name="generator" content="BBEdit Lite v6.1"><meta name="publisher" content="<<company>>"><meta name="copyright" content="<<copyright>>">|g;
	
	s|<<stylesheet\s+([^>]+)>>|<link rel="stylesheet" href="$1.css" type="text/css">|g;
	s|<<body>>|<body>|g;
	s|<<footer>>|<div id="page_footer"><hr width=520><<copyright>><br><<company-web>></div><br><br>|g;
	
	s|<<a\s+mailtome>>|<<a mailto>><<email>></a>|g;
	s|<<a\s+mailto\s+(\S+)>>|<a href="mailto:$1">|g;
	s|<<a\s+mailto>>|<a href="mailto:<<email>>">|g;
	
	s|<<copyright>>|(c) $year <<author>>, <<company>>|g;
	s|<<author>>|Firstname Lastname|g;
	s|<<company>>|Example Company Name|g;
	s|<<company-web>>|www.example.com|g;
	s|<<email>>|info\@example.com|g;
	
	s|$|</body></html>| unless ( m|</body>\s*</html>\s*$| );
    }
}



# =========================================================================
# post_process()
# =========================================================================
#
# optional post_processing
#
# You can use this to run quality checks on the resulting code.

sub post_process($$)
{
    my ( $filename, $type ) = @_;

    # Warn us about any remaining ?content-placeholders?.
    my @list = ();
    while ( m|(\?[a-z-]+\?)|igc )  { push ( @list, $1 ); }
    print STDERR "Warning: Content placeholders found: " . join( ", ", @list ) if @list;
}



1;  # don't forget to return a true value from the file
