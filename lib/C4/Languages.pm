package C4::Languages;

# Copyright 2006 (C) LibLime
# Joshua Ferraro <jmf@liblime.com>
# Portions Copyright 2009 Chris Cormack and the Koha Dev Team
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# Koha; if not, write to the Free Software Foundation, Inc., 59 Temple Place,
# Suite 330, Boston, MA  02111-1307 USA


use Carp;
use Koha;
use C4::Context;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $DEBUG);

BEGIN {
    $VERSION = 3.00;
    require Exporter;
    @ISA    = qw(Exporter);
    @EXPORT = qw(
        &getTranslatedLanguages
        &getAllLanguages
    );
    @EXPORT_OK = qw(getTranslatedLanguages getAllLanguages get_bidi regex_lang_subtags language_get_description accept_language);
    $DEBUG = 0;
}

=head1 NAME

C4::Languages - Perl Module containing language list functions for Koha 

=head1 SYNOPSIS

use C4::Languages;

=head1 DESCRIPTION

=head1 FUNCTIONS

=head2 getTranslatedLanguages

Returns a reference to an array of hashes:

 my $languages = getTranslatedLanguages();
 print "Available translated languages:\n";
 for my $language(@$trlanguages) {
    print "$language->{language_code}\n"; # language code in iso 639-2
    print "$language->{language_name}\n"; # language name in native script
    print "$language->{language_locale_name}\n"; # language name in current locale
 }

=cut

sub getTranslatedLanguages {
    my ($interface, $theme, $current_language, $which) = @_;
    my $htdocs;
    my $all_languages = getAllLanguages();
    my @languages;
    my @enabled_languages;
 
    if ($interface && $interface eq 'opac' ) {
        @enabled_languages = split ",", C4::Context->preference('opaclanguages');
        $htdocs = C4::Context->config('opachtdocs');
        if ( $theme and -d "$htdocs/$theme" ) {
            (@languages) = _get_language_dirs($htdocs,$theme);
        }
        else {
            for my $theme ( _get_themes('opac') ) {
                push @languages, _get_language_dirs($htdocs,$theme);
            }
        }
    }
    elsif ($interface && $interface eq 'intranet' ) {
        @enabled_languages = split ",", C4::Context->preference('language');
        $htdocs = C4::Context->config('intrahtdocs');
        if ( $theme and -d "$htdocs/$theme" ) {
            @languages = _get_language_dirs($htdocs,$theme);
        }
        else {
            foreach my $theme ( _get_themes('intranet') ) {
                push @languages, _get_language_dirs($htdocs,$theme);
            }
        }
    }
    else {
        @enabled_languages = split ",", C4::Context->preference('opaclanguages');
        my $htdocs = C4::Context->config('intrahtdocs');
        foreach my $theme ( _get_themes('intranet') ) {
            push @languages, _get_language_dirs($htdocs,$theme);
        }
        $htdocs = C4::Context->config('opachtdocs');
        foreach my $theme ( _get_themes('opac') ) {
            push @languages, _get_language_dirs($htdocs,$theme);
        }
        my %seen;
        $seen{$_}++ for @languages;
        @languages = keys %seen;
    }
    return _build_languages_arrayref($all_languages,\@languages,$current_language,\@enabled_languages);
}

=head2 getAllLanguages

Returns a reference to an array of hashes:

 my $alllanguages = getAllLanguages();
 print "Available translated languages:\n";
 for my $language(@$alllanguages) {
    print "$language->{language_code}\n";
    print "$language->{language_name}\n";
    print "$language->{language_locale_name}\n";
 }

=cut

sub _seed_languages_cache {
    my $current_language = shift;

    my $langs_query =
        q{SELECT lsr.subtag, lsr.added, lsr.type, lsr.description, lrti.iso639_2_code, lsr.id,
            CONCAT(ld1.description, ' (', ld2.description, ')') language_description
          FROM language_subtag_registry lsr
            LEFT JOIN language_rfc4646_to_iso639 lrti
              ON (lsr.subtag = lrti.rfc4646_subtag)
            LEFT JOIN language_descriptions ld1
              ON (ld1.subtag = lsr.subtag)
            LEFT JOIN language_descriptions ld2
              ON (ld2.subtag = lsr.subtag)
          WHERE lsr.type = 'language'
            AND ld1.type = 'language'
            AND ld2.type = 'language'
            AND ld1.lang = lsr.subtag
            AND ld2.lang = ?
    };
    my $langs = C4::Context->dbh->selectall_arrayref(
        $langs_query, { Slice=>{} }, $current_language);

    return $langs;
}

sub getAllLanguages {
    my $current_language = shift || 'en';
    my $cache = C4::Context->getcache(__PACKAGE__,
                                      {driver => 'RawMemory',
                                       datastore => C4::Context->cachehash});
    my $langs = $cache->compute(
        'all_languages:$current_language', '5m',
        sub {_seed_languages_cache($current_language)});
    return $langs;
}

=head2 _get_themes

Internal function, returns an array of all available themes.

  (@themes) = &_get_themes('opac');
  (@themes) = &_get_themes('intranet');

=cut

sub _get_themes {
    my $interface = shift;
    my $htdocs;
    my @themes;
    if ( $interface eq 'intranet' ) {
        $htdocs = C4::Context->config('intrahtdocs');
    }
    else {
        $htdocs = C4::Context->config('opachtdocs');
    }
    opendir D, "$htdocs";
    my @dirlist = readdir D;
    foreach my $directory (@dirlist) {
        # if there's an en dir, it's a valid theme
        -d "$htdocs/$directory/en" and push @themes, $directory;
    }
    return @themes;
}

=head2 _get_language_dirs

Internal function, returns an array of directory names, excluding non-language directories

=cut

sub _get_language_dirs {
    my ($htdocs,$theme) = @_;
    my @lang_strings;
    opendir D, "$htdocs/$theme";
    for my $lang_string ( readdir D ) {
        next if $lang_string =~/^\./;
        next if $lang_string eq 'all';
        next if $lang_string =~/png$/;
        next if $lang_string =~/css$/;
        next if $lang_string =~/CVS$/;
        next if $lang_string =~/\.txt$/i;     #Don't read the readme.txt !
        next if $lang_string =~/img|images|famfam|sound/;
        push @lang_strings, $lang_string;
    }
        return (@lang_strings);
}

=head2 _build_languages_arrayref 

Internal function for building the ref to array of hashes

FIXME: this could be rewritten and simplified using map

=cut

sub _build_languages_arrayref {
        my ($all_languages,$translated_languages,$current_language,$enabled_languages) = @_;
        my @translated_languages = @$translated_languages;
        my @languages_loop; # the final reference to an array of hashrefs
        my @enabled_languages = @$enabled_languages;
        # how many languages are enabled, if one, take note, some contexts won't need to display it
        my %seen_languages; # the language tags we've seen
        my %found_languages;
        my $language_groups;
        my $track_language_groups;
        my $current_language_regex = regex_lang_subtags($current_language);
        # Loop through the translated languages
        for my $translated_language (@translated_languages) {
            # separate the language string into its subtag types
            my $language_subtags_hashref = regex_lang_subtags($translated_language);

            # is this language string 'enabled'?
            for my $enabled_language (@enabled_languages) {
                #warn "Checking out if $translated_language eq $enabled_language";
                $language_subtags_hashref->{'enabled'} = 1 if $translated_language eq $enabled_language;
            }
            
            # group this language, key by langtag
            $language_subtags_hashref->{'sublanguage_current'} = 1 if $translated_language ~~ $current_language;
            $language_subtags_hashref->{'rfc4646_subtag'} = $translated_language;
            $language_subtags_hashref->{'native_description'} = language_get_description($language_subtags_hashref->{language},$language_subtags_hashref->{language},'language');
            $language_subtags_hashref->{'script_description'} = language_get_description($language_subtags_hashref->{script},$language_subtags_hashref->{'language'},'script');
            $language_subtags_hashref->{'region_description'} = language_get_description($language_subtags_hashref->{region},$language_subtags_hashref->{'language'},'region');
            $language_subtags_hashref->{'variant_description'} = language_get_description($language_subtags_hashref->{variant},$language_subtags_hashref->{'language'},'variant');
            $track_language_groups->{$language_subtags_hashref->{'language'}}++;
            push ( @{ $language_groups->{$language_subtags_hashref->{language}} }, $language_subtags_hashref );
        }
        # $key is a language subtag like 'en'
        while( my ($key, $value) = each %$language_groups) {

            # is this language group enabled? are any of the languages within it enabled?
            my $enabled;
            for my $enabled_language (@enabled_languages) {
                my $regex_enabled_language = regex_lang_subtags($enabled_language);
                $enabled = 1 if $key eq $regex_enabled_language->{language};
            }
            push @languages_loop,  {
                            # this is only use if there is one
                            rfc4646_subtag => @$value[0]->{rfc4646_subtag},
                            native_description => language_get_description($key,$key,'language'),
                            language => $key,
                            sublanguages_loop => $value,
                            plural => $track_language_groups->{$key} >1 ? 1 : 0,
                            current => $current_language_regex->{language} ~~ $key ? 1 : 0,
                            group_enabled => $enabled,
                           };
        }
        return \@languages_loop;
}

sub _seed_language_description_cache {
    return C4::Context->dbh->selectall_hashref(
        'SELECT description, subtag, lang, type FROM language_descriptions',
        [qw(subtag lang type)], { Slice=>{} });
}

sub language_get_description {
    my ($subtag,$lang,$type) = @_;
    my $cache = C4::Context->getcache(__PACKAGE__,
                                      {driver => 'RawMemory',
                                       datastore => C4::Context->cachehash});
    my $descriptions = $cache->compute(
        'language_descriptions', '5m',
        \&_seed_language_description_cache);
    no warnings qw(uninitialized);
    my $lang_desc = $descriptions->{$subtag}{$lang}{$type};
    return ($lang_desc) ? $lang_desc->{description} : 'English';
}

=head2 regex_lang_subtags

This internal sub takes a string composed according to RFC 4646 as
an input and returns a reference to a hash containing keys and values
for ( language, script, region, variant, extension, privateuse )

=cut

sub regex_lang_subtags {
    my $string = shift;

    # Regex for recognizing RFC 4646 well-formed tags
    # http://www.rfc-editor.org/rfc/rfc4646.txt

    # regexes based on : http://unicode.org/cldr/data/tools/java/org/unicode/cldr/util/data/langtagRegex.txt
    # The structure requires no forward references, so it reverses the order.
    # The uppercase comments are fragments copied from RFC 4646
    #
    # Note: the tool requires that any real "=" or "#" or ";" in the regex be escaped.

    my $alpha   = qr/[a-zA-Z]/ ;    # ALPHA
    my $digit   = qr/[0-9]/ ;   # DIGIT
    my $alphanum    = qr/[a-zA-Z0-9]/ ; # ALPHA / DIGIT
    my $x   = qr/[xX]/ ;    # private use singleton
    my $singleton = qr/[a-w y-z A-W Y-Z]/ ; # other singleton
    my $s   = qr/[-]/ ; # separator -- lenient parsers will use [-_]

    # Now do the components. The structure is slightly different to allow for capturing the right components.
    # The notation (?:....) is a non-capturing version of (...): so the "?:" can be deleted if someone doesn't care about capturing.

    my $extlang = qr{(?: $s $alpha{3} )}x ; # *3("-" 3ALPHA)
    my $language    = qr{(?: $alpha{2,3} | $alpha{4,8} )}x ;
    #my $language   = qr{(?: $alpha{2,3}$extlang{0,3} | $alpha{4,8} )}x ;   # (2*3ALPHA [ extlang ]) / 4ALPHA / 5*8ALPHA

    my $script  = qr{(?: $alpha{4} )}x ;    # 4ALPHA 

    my $region  = qr{(?: $alpha{2} | $digit{3} )}x ;     # 2ALPHA / 3DIGIT

    my $variantSub  = qr{(?: $digit$alphanum{3} | $alphanum{5,8} )}x ;  # *("-" variant), 5*8alphanum / (DIGIT 3alphanum)
    my $variant = qr{(?: $variantSub (?: $s$variantSub )* )}x ; # *("-" variant), 5*8alphanum / (DIGIT 3alphanum)

    my $extensionSub    = qr{(?: $singleton (?: $s$alphanum{2,8} )+ )}x ;   # singleton 1*("-" (2*8alphanum))
    my $extension   = qr{(?: $extensionSub (?: $s$extensionSub )* )}x ; # singleton 1*("-" (2*8alphanum))

    my $privateuse  = qr{(?: $x (?: $s$alphanum{1,8} )+ )}x ;   # ("x"/"X") 1*("-" (1*8alphanum))

    # Define certain grandfathered codes, since otherwise the regex is pretty useless.
    # Since these are limited, this is safe even later changes to the registry --
    # the only oddity is that it might change the type of the tag, and thus
    # the results from the capturing groups.
    # http://www.iana.org/assignments/language-subtag-registry
    # Note that these have to be compared case insensitively, requiring (?i) below.

    my $grandfathered   = qr{(?: (?i)
        en $s GB $s oed
    |   i $s (?: ami | bnn | default | enochian | hak | klingon | lux | mingo | navajo | pwn | tao | tay | tsu )
    |   sgn $s (?: BE $s fr | BE $s nl | CH $s de)
)}x;

    # For well-formedness, we don't need the ones that would otherwise pass, so they are commented out here

    #   |   art $s lojban
    #   |   cel $s gaulish
    #   |   en $s (?: boont | GB $s oed | scouse )
    #   |   no $s (?: bok | nyn)
    #   |   zh $s (?: cmn | cmn $s Hans | cmn $s Hant | gan | guoyu | hakka | min | min $s nan | wuu | xiang | yue)

    # Here is the final breakdown, with capturing groups for each of these components
    # The language, variants, extensions, grandfathered, and private-use may have interior '-'

    #my $root = qr{(?: ($language) (?: $s ($script) )? 40% (?: $s ($region) )? 40% (?: $s ($variant) )? 10% (?: $s ($extension) )? 5% (?: $s ($privateuse) )? 5% ) 90% | ($grandfathered) 5% | ($privateuse) 5% };

    my %subtag;
    {
        no warnings qw(uninitialized);
        $string =~  qr{^ (?:($language)) (?:$s($script))? (?:$s($region))?  (?:$s($variant))?  (?:$s($extension))?  (?:$s($privateuse))? $}xi;  # |($grandfathered) | ($privateuse) $}xi;
        %subtag = (
            'rfc4646_subtag' => $string,
            'language' => $1,
            'script' => $2,
            'region' => $3,
            'variant' => $4,
            'extension' => $5,
            'privateuse' => $6,
        );
    }
    return \%subtag;
}

# Script Direction Resources:
# http://www.w3.org/International/questions/qa-scripts
sub get_bidi {
    my ($language_script)= @_;
    my $dbh = C4::Context->dbh;
    my $bidi;
    my $sth = $dbh->prepare('SELECT bidi FROM language_script_bidi WHERE rfc4646_subtag=?');
    $sth->execute($language_script);
    while (my $result = $sth->fetchrow_hashref) {
        $bidi = $result->{'bidi'};
    }
    return $bidi;
};

sub accept_language {
    # referenced http://search.cpan.org/src/CGILMORE/I18N-AcceptLanguage-1.04/lib/I18N/AcceptLanguage.pm
    # FIXME: since this is only used in Output.pm as of Jan 8 2008, maybe it should be IN Output.pm
    my ($clientPreferences,$supportedLanguages) = @_;
    my @languages = ();
    if ($clientPreferences) {
        # There should be no whitespace anways, but a cleanliness/sanity check
        $clientPreferences =~ s/\s//g;
        # Prepare the list of client-acceptable languages
        foreach my $tag (split(/,/, $clientPreferences)) {
            my ($language, $quality) = split(/\;/, $tag);
            $quality =~ s/^q=//i if $quality;
            $quality = 1 unless $quality;
            next if $quality <= 0;
            # We want to force the wildcard to be last
            $quality = 0 if ($language eq '*');
            # Pushing lowercase language here saves processing later
            push(@languages, { quality => $quality,
               language => $language,
               lclanguage => lc($language) });
        }
    } else {
        carp "accept_language(x,y) called with no clientPreferences (x).";
    }
    # Prepare the list of server-supported languages
    my %supportedLanguages = ();
    my %secondaryLanguages = ();
    foreach my $language (@$supportedLanguages) {
        # warn "Language supported: " . $language->{language};
        my $subtag = $language->{rfc4646_subtag};
        $supportedLanguages{lc($subtag)} = $subtag;
        if ( $subtag =~ /^([^-]+)-?/ ) {
            $secondaryLanguages{lc($1)} = $subtag;
        }
    }

    # Reverse sort the list, making best quality at the front of the array
    @languages = sort { $b->{quality} <=> $a->{quality} } @languages;
    my $secondaryMatch = '';
    foreach my $tag (@languages) {
        if (exists($supportedLanguages{$tag->{lclanguage}})) {
            # Client en-us eq server en-us
            return $supportedLanguages{$tag->{language}} if exists($supportedLanguages{$tag->{language}});
            return $supportedLanguages{$tag->{lclanguage}};
        } elsif (exists($secondaryLanguages{$tag->{lclanguage}})) {
            # Client en eq server en-us
            return $secondaryLanguages{$tag->{language}} if exists($secondaryLanguages{$tag->{language}});
            return $supportedLanguages{$tag->{lclanguage}};
        } elsif ($tag->{lclanguage} =~ /^([^-]+)-/ && exists($secondaryLanguages{$1}) && $secondaryMatch eq '') {
            # Client en-gb eq server en-us
            $secondaryMatch = $secondaryLanguages{$1};
        } elsif ($tag->{lclanguage} =~ /^([^-]+)-/ && exists($secondaryLanguages{$1}) && $secondaryMatch eq '') {
            # FIXME: We just checked the exact same conditional!
            # Client en-us eq server en
            $secondaryMatch = $supportedLanguages{$1};
        } elsif ($tag->{lclanguage} eq '*') {
        # * matches every language not already specified.
        # It doesn't care which we pick, so let's pick the default,
        # if available, then the first in the array.
        #return $acceptor->defaultLanguage() if $acceptor->defaultLanguage();
        return $supportedLanguages->[0];
        }
    }
    # No primary matches. Secondary? (ie, en-us requested and en supported)
    return $secondaryMatch if $secondaryMatch;
    return undef;   # else, we got nothing.
}
1;

__END__

=head1 AUTHOR

Joshua Ferraro

=cut
