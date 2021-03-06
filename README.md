# htmlXPress

This is a Perl-based solution to compress, and to process HTML and CSS files.

The `htmlXPress.pl` script removes embedded comments and unnecessary whitespace, while leaving the formatting of the page intact. Embedded PHP code or Javascript are also not harmed.

Before this compression takes place, the script also expands custom macros like `<:date:>` (note the `<:` and `:>`) which will be replaced with today's date.

You can easily extend the processing with your own macros and other site-specific Perl code.


# Example

Two example files are provided in the example directory, an HTML file and a CSS file. To run the script, you can call it directly from a command prompt:

```csh
% cd example
% ../htmlXPress.pl -out results example.html
% ../htmlXPress.pl -out results example.css
```

Or you can use the `MakeFile` in the example directory:

```csh
% cd example
% make
```

The compressed files are placed in the `example/results` directory.

For examples of more complex HTML pages, compressed by htmlXPress, you can take a look at the page sources for the files at http://tredje.se.


# Installation

You need to have [Perl](www.perl.org) installed, probably at least Perl 5. On UNIX/Linux-based systems (incl. Mac OS X), Perl is generally pre-installed. On a terminal prompt, you can try `perl --version` to check.

Copy the `htmlXPress.pl` file into a directory of your choice; just make sure its file permissions allow it to be executed (`chmod 750 htmlXPress.pl`). Also, if you use a Makefile similar to the one in the example folder, you will need to adjust the path to be able to locate your copy of the script. For instance:

```make
HXP=/usr/local/scripts/htmlXPress.pl
OUT=/Users/goblin/Sites/my_site

...
```

Optionally, you can create a user-specific configuration file: `~/.htmlxpressrc` (see below).


# Usage

```
htmlXPress.pl [Options] file_to_compress
```

### Options

#### -(no)banner

Using **-banner** (default) will add an htmlXPress version banner in the output. To disable, use **-nobanner**.

#### -(no)href_check

To check embedded links, use **-href_check**. The default is **-nohref_check**.

#### -(no)debug

The **-debug** option will output additional progress messages and variable settings. The default is **-nodebug**. For regular use, you may prefer **-verbose**.

#### -help | -usage

With **-help** or **-usage**, you will be presented with a short usage info and no processing is done. When issued twice, the usage info will be more detailed.

#### -inplace | -overwrite

Use with extreme caution! This option will irreversibly overwrite the orignial file. Try not to use this. Instead, use **-out** to write the results into a different directory.

#### -(no)lint

For XHTML (or files that are in XML format), the **-lint** option will call "xmllint" to run a syntax check on the generated output file. The default is **-nolint**.

#### -out dir_name

Our favourite option: Use **-out** to specify into which directory the result file should be placed. As an alternative, the config file or the site file may specify the output directory throught the **$destination** variable (see below).

#### -(no)verbose

When given, **-verbose** will produce a set of progress messages. The default is **-noverbose**. For even more messages, use **-debug**.


# Configuration

You can create a config file in your home directory, named `.htmlxpressrc` in which you can predefine a set of variables (following ordinary Perl syntax). Here are all the default settings, none of which are used as they are turned off with comment characters "##":

```perl
# ~/.htmlxpressrc - config for htmlXPress.pl

# The HTML-like markers that are used to delimit custom macros.
# Example: <<date>> or <:date:>.
## $hxpr_beg = "(?:<<|<:)";
## $hxpr_end = "(?:>>|:>)";

# Whether to add an htmlXPress version banner.
## $add_banner = 1;

# The path to the curl executable.
## $curl_exec = "/usr/bin/curl";

# The date format to use in POSIX::strftime format.
## $date_format = "%Y-%m-$d";

# The default Macintosh creator code applied to the output files.
## $default_creator = "";

# The name of the output directory:
## $destination = "";

# The mapping of file extensions and how to handle them:
## %file_table = {};    # see htmlXPress.pl for an example

# The path to the SetFile executable to set Macintosh creator codes:
## $set_file_exec = "/usr/bin/SetFile";

# The name of the site package file, e.g. "site" (in file "site.pm"):
## $site_package_name = "site";

# The XML lint command:
## $xml_lint_commant = "/usr/bin/xmllint -noout";
```


# Customization

You can add your personal macros or replacement rules using your own Perl code.

By default, any code that you have placed in a "site.pm" module file will be loaded. Within that module, you would define `&pre_process`, `&process`, and `&post_process` sub-routines which will be executed once for each file.

Additionally, you can define new settings for the same variables as in the config file (see above); just declare them with `our`:

```perl
# site.pm
package site;

# Where to place the resulting files:
our $destination = "/Library/Web Pages/";

sub process($$)
{
    my ( $filename, $type ) = @_;       # e.g. "example.html", "html"

    s|<:email:>|info\@example.com|g;    # <:email:>  ->  info@example.com
}

1;  # always return a true value!
```


# Variables

All variables are described in the header section of the `htmlXPress.pl` script. The `%file_table` deserves special mentioning as it controls how selected file types are handled:

#### %file_table

The `%file_table` variable contains a hash table, mapping file extensions to settings that should be used for files of that type. The default settings for files are:

```perl
%file_table = {
    default => {
        info => "default settings",
        compress => 0,
        creator => "",          # set to $default_creator below
        non_ascii => 0,
        textwidth => 0,
    },
};
```

In detail: There is no file compression (`compress => 0`), no specific Macintosh creator code (`creator => ""`), no non-ASCII character handling (`non_ascii => 0`), and the output text is not wrapped (`textwidth => 0`). NB. The info string is ignored.

For HTML files to be compressed, another entry in the `%file_table` is predefined for the .html and .htm file extensions:

```perl
%file_table = {
    html => {
        info => "Hypert-text markup langage",
        compress => 2,
        non_ascii => 1,
        textwidth => 80,
    },

    # As above for HTML.
    htm => { copy_from => "html" },
};
````

In detail: Files with the .html extension will be fully compressed (`compress => 2`), non-ASCII characters will be converted (`non_ascii => 1`), and if possible, the compressed output is line-wrapped to 80 characters (`textwidth => 80`). File ending in .htm use the same settings as .html files.

To add your own file type, you can declare it in the site package file. An example is provided in the "site.pm" file within the example directory.


# Macros

The following macros are predefined:

| Macro         | Description
| :------------ | :--------------------------------------------------------
| `<:date:>`    | Is replaced by today's date, using the format specified in the $date_format variable.
| `<:longdate:>`| Is replaced by today's date, using the default format of your locale.
| `<:file:>`    | Is replaced by the current file name.
| `<:nowrap:>`  | Is removed. It disables text wrapping for this file.


Also, there are some handy shortcuts that are available when non-ASCII character replacement is enabled (these changed in version 4.1):

| Shortcut      | Replacement   | Description
| :------------ | :-------------| :-----------------------------------------
| `\ `          | `&nbsp;`      | A backslash before a space: Non-Breaking Space
| `\&`          | `&amp;`       | Ampersand (&)
| `\<`          | `&lt;`        | Less Than (<)
| `\>`          | `&gt;`        | Greater Than (>)


# Known Issues

* The handling of `&` (changed to `&amp;`) and `\&` (changed to `&`) has changed in version 4.1. You may need to adjust the URLs in your sources from the form: "host/?a=0&b=0" to "host/?a=0\&b=0", i.e. with the backslash that will be removed.

* Text wrapping is a purely cosmetic feature that has no practical use. It is disabled whenever embedded JavaScript code is detected (or when you have added the `<<nowrap>>` marker macro). You should note that certain constructs (like very long URLs) can never be wrapped without breaking the functionality of the page. Therefore, the resulting lines may well exceed the limit that you have specified for the "textwidth".

* Input files need to be UTF-8 encoded to be able to correctly detect any non-ASCII characters.


# History

Back in 1999, htmlXPress originally evolved as a MacPerl droplet on Mac OS 9. Thankfully, with Mac OS X, it now works straight out of the box.

The complete version history is available on [tredje.se](http://tredje.se/history.html?p=hxpr).
