package BibSpace::Controller::Publications;

use Data::Dumper;
use utf8;
use Text::BibTeX;    # parsing bib files
use DateTime;
use File::Slurp;     # should be replaced in the future
use Path::Tiny;      # for creating directories
use Try::Tiny;
use Time::Piece;
use 5.010;           #because of ~~
use strict;
use warnings;
use DBI;

use TeX::Encode;
use Encode;
use Mojo::Redis2;

use BibSpace::Controller::Core;
use BibSpace::Functions::FPublications;
use BibSpace::Model::MEntry;
use BibSpace::Model::MTag;

# use BibSpace::Controller::Set;
use BibSpace::Functions::FSet;

use Set::Scalar;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::Base 'Mojolicious::Plugin::Config';
use Mojo::UserAgent;
use Mojo::Log;

our %mons = (
    1  => 'January',
    2  => 'February',
    3  => 'March',
    4  => 'April',
    5  => 'May',
    6  => 'June',
    7  => 'July',
    8  => 'August',
    9  => 'September',
    10 => 'October',
    11 => 'November',
    12 => 'December'
);
####################################################################################
sub fixMonths {
    my $self = shift;

    my ( $processed_entries, $fixed_entries ) = Ffix_months( $self->app->db );
    $self->flash( msg =>
            'Fixing entries month field finished. Number of entries checked/fixed: '
            . $processed_entries . "/"
            . $fixed_entries );
    $self->redirect_to( $self->get_referrer );
}
####################################################################################
sub fixEntryType {
    my $self = shift;

    my @objs      = MEntry->static_all( $self->app->db );
    my $num_fixes = 0;
    for my $e (@objs) {

       # $num_fixes = $num_fixes + $o->fixEntryTypeBasedOnTag($self->app->db);
        $num_fixes
            = $num_fixes + $e->fix_entry_type_based_on_tag( $self->app->db );
    }

    $self->flash( msg =>
            'All entries have now their paper/talk type fixed. Number of fixes: '
            . $num_fixes );
    $self->redirect_to( $self->get_referrer );
}
####################################################################################
sub unhide {
    my $self = shift;
    my $id   = $self->param('id');
    my $dbh  = $self->app->db;

    my $mentry = MEntry->static_get( $dbh, $id );
    if ( !defined $mentry ) {
        $self->flash( msg => "There is no entry with id $id" );
        $self->redirect_to( $self->get_referrer );
        return;
    }
    $mentry->unhide($dbh);

    $self->redirect_to( $self->get_referrer );
}

####################################################################################
sub hide {
    my $self = shift;
    my $id   = $self->param('id');

    my $mentry = MEntry->static_get( $self->app->db, $id );
    if ( defined $mentry ) {
        $mentry->hide( $self->app->db );
    }
    else {
        $self->flash( msg => "There is no entry with id $id" );
    }
    $self->redirect_to( $self->get_referrer );
}
####################################################################################
sub toggle_hide {
    my $self = shift;
    my $id   = $self->param('id');
    my $dbh  = $self->app->db;

    my $mentry = MEntry->static_get( $dbh, $id );
    if ( !defined $mentry ) {
        $self->flash( msg => "There is no entry with id $id" );
        $self->redirect_to( $self->get_referrer );
        return;
    }
    $mentry->toggle_hide($dbh);

    $self->redirect_to( $self->get_referrer );
}
####################################################################################
sub make_paper {
    my $self = shift;
    my $id   = $self->param('id');
    my $dbh  = $self->app->db;

    my $mentry = MEntry->static_get( $dbh, $id );
    if ( !defined $mentry ) {
        $self->flash( msg => "There is no entry with id $id" );
        $self->redirect_to( $self->get_referrer );
        return;
    }
    $mentry->make_paper($dbh);

    $self->redirect_to( $self->get_referrer );
}
####################################################################################
sub make_talk {
    my $self = shift;
    my $id   = $self->param('id');
    my $dbh  = $self->app->db;

    my $mentry = MEntry->static_get( $dbh, $id );
    if ( !defined $mentry ) {
        $self->flash( msg => "There is no entry with id $id" );
        $self->redirect_to( $self->get_referrer );
        return;
    }
    $mentry->make_talk($dbh);

    $self->redirect_to( $self->get_referrer );
}
####################################################################################
sub all_recently_added {
    my $self = shift;
    my $num  = $self->param('num') || 10;
    my $dbh  = $self->app->db;

    my @objs = sort { $b->{creation_time} cmp $a->{creation_time} }
        MEntry->static_all( $self->app->db );
    @objs = @objs[ 0 .. $num ];

    # map {say $_->{creation_time}} @objs;

    $self->stash( entries => \@objs );
    $self->render( template => 'publications/all' );
}
####################################################################################

sub all_recently_modified {
    my $self = shift;
    my $num  = $self->param('num') || 10;
    my $dbh  = $self->app->db;

    my @objs = sort { $b->{modified_time} cmp $a->{modified_time} }
        MEntry->static_all( $self->app->db );
    @objs = @objs[ 0 .. $num ];

    # map {say $_->{modified_time}} @objs;

    $self->stash( entries => \@objs );
    $self->render( template => 'publications/all' );
}

####################################################################################
sub all_without_tag {
    my $self    = shift;
    my $tagtype = $self->param('tagtype') || 1;
    my $dbh     = $self->app->db;

    my @all = MEntry->static_all($dbh);
    my @objs = grep { scalar $_->tags( $dbh, $tagtype ) == 0 } @all;


    my $msg
        = "This list contains papers that have no tags of type $tagtype. Use this list to tag the untagged papers! ";
    $self->stash( msg_type => 'info', msg => $msg );
    $self->stash( entries => \@objs );
    $self->render( template => 'publications/all' );
}
####################################################################################
sub all_without_tag_for_author {
    my $self        = shift;
    my $dbh         = $self->app->db;
    my $master_name = $self->param('author');
    my $tagtype     = $self->param('tagtype');

    my $author = MAuthor->static_get_by_master( $dbh, $master_name );
    $author = MAuthor->static_get( $dbh, $master_name ) if !defined $author;

    # no such master. Assume, that author id was given

    my @all_author_entries = $author->entries($dbh);
    my @objs
        = grep { scalar $_->tags( $dbh, $tagtype ) == 0 } @all_author_entries;


    my $msg
        = "This list contains papers of $author->{master} that miss tags of type $tagtype. ";
    $self->stash( entries => \@objs, msg_type => 'info', msg => $msg );
    $self->render( template => 'publications/all' );
}
####################################################################################
sub all_without_author {
    my $self = shift;
    my $dbh  = $self->app->db;

    my @objs
        = grep { scalar $_->authors($dbh) == 0 } MEntry->static_all($dbh);

    my $msg
        = "This list contains papers, that are currently not assigned to any of authors.";
    $self->stash( entries => \@objs, msg => $msg, msg_type => 'info' );
    $self->render( template => 'publications/all' );
}

####################################################################################
sub show_unrelated_to_team {
    my $self    = shift;
    my $team_id = $self->param('teamid');
    my $dbh     = $self->app->db;

    $self->write_log(
        "Displaying entries unrelated to team with it $team_id.");

    my $set_all_papers
        = Set::Scalar->new( map { $_->{id} } MEntry->static_all($dbh) );
    my $set_of_related_to_team
        = Fget_set_of_papers_for_all_authors_of_team_id( $dbh, $team_id );
    my $end_set = $set_all_papers - $set_of_related_to_team;

    my $team_name = "";
    my $mteam = MTeam->static_get( $dbh, $team_id );
    $team_name = $mteam->{name} if defined $mteam;

    my $msg = "This list contains papers, that are:
        <ul>
            <li>Not assigned to the team "
        . $team_name . "</li>
            <li>Not assigned to any author (former or actual) of the team "
        . $team_name . "</li>
        </ul>";

    my @objs = Fget_publications_core_from_set( $self, $end_set );
    $self->stash( msg_type => 'info', msg => $msg );
    $self->stash( entries => \@objs );
    $self->render( template => 'publications/all' );
}
####################################################################################
sub all_with_missing_month {
    my $self = shift;
    my $dbh  = $self->app->db;

    $self->write_log("Displaying entries without month");

    my @objs
        = grep { !defined $_->{month} or $_->{month} < 1 or $_->{month} > 12 }
        MEntry->static_all($dbh);

    my $msg
        = "This list contains entries with missing BibTeX field 'month'. ";
    $msg .= "Add this data to get the proper chronological sorting.";

    $self->stash( msg_type => 'info', msg => $msg );
    $self->stash( entries => \@objs );
    $self->render( template => 'publications/all' );
}
####################################################################################
sub all_candidates_to_delete {
    my $self = shift;
    my $dbh  = $self->app->db;

    $self->write_log("Displaying entries that are candidates_to_delete");


    my @objs = MEntry->static_all( $self->app->db );
    @objs = grep { scalar $_->tags($dbh) == 0 } @objs;  # no tags
    @objs = grep { scalar $_->teams($dbh) == 0 } @objs; # no relation to teams
    @objs = grep { scalar $_->exceptions($dbh) == 0 } @objs;   # no exceptions


    my $msg = "<p>This list contains papers, that are:</p>
      <ul>
          <li>Not assigned to any team AND</li>
          <li>have exactly 0 tags AND</li>
          <li>not assigned to any author that is (or was) a member of any team AND </li>
          <li>have exactly 0 exceptions assigned.</li>
      </ul>
      <p>Such entries may wanted to be removed form the system or serve as a help with configuration.</p>";

    $self->stash( msg_type => 'info', msg => $msg );
    $self->stash( entries => \@objs );
    $self->render( template => 'publications/all' );
}

####################################################################################

sub all_bibtex {
    my $self = shift;

    my $entry_type = undef;
    $entry_type = $self->param('entry_type') // 'paper';

    my @objs = Fget_publications_main_hashed_args( $self,
        { hidden => 0, entry_type => $entry_type } );

    my $big_str = "<pre>\n";
    foreach my $obj (@objs) {
        $big_str .= $obj->{bib};
        $big_str .= "\n";
    }
    $big_str .= "\n</pre>";
    $self->render( text => $big_str );
}
####################################################################################
sub all {
    my $self = shift;

    my $entry_type = undef;
    $entry_type = $self->param('entry_type') // 'paper';

    if ( $self->session('user') ) {
        # check cache
        my $key = "publications." . join("_", @{$self->req->params->pairs} );
        my $html = $self->app->redis->get($key);

        if($html){
            $self->render(data => $html);
            # TODO: update cache in background - must be non-blocking to make sense!
            return;
        }

        $self->render_later;
        $self->delay( 
            sub{
                my @objs = Fget_publications_main_hashed_args( $self,
                { entry_type => $entry_type } );
        
                $self->stash( entries => \@objs );
                $html = $self->render_to_string( template => 'publications/all' );
                $self->app->redis->set($key => $html  );
            },
            sub { 
                $self->render(data => $html);
            },
        );
    }
    else {
        return $self->all_read();
    }
}

####################################################################################

sub all_read {
    my $self = shift;

    my $key = "publications.read." . join("_", @{$self->req->params->pairs} );
    my $html = $self->app->redis->get($key);
    if($html){
        $self->render(data => $html);
        # TODO: update cache in background - must be non-blocking to make sense!
        return;
    }

    my @objs = Fget_publications_main_hashed_args( $self,
        { hidden => 0, entry_type => undef } );

    $self->stash( entries => \@objs );
    $html = $self->render_to_string( template => 'publications/all_read' );
    $self->app->redis->set($key => $html  );
    $self->render( data => $html );
}

####################################################################################

sub single {
    my $self = shift;
    my $id   = $self->param('id');

    my @objs = ();
    my $e = MEntry->static_get( $self->app->db, $id );
    if ( defined $e ) {
        push @objs, $e;
    }
    else {
        $self->stash(
            msg_type => 'danger',
            msg      => "Entry $id does not exist."
        );
    }
    $self->stash( entries => \@objs );
    $self->render( template => 'publications/all' );
}

####################################################################################

sub single_read {
    my $self = shift;
    my $id   = $self->param('id');

    my @objs = ();
    my $e = MEntry->static_get( $self->app->db, $id );

    if ( defined $e and $e->is_hidden == 0 ) {
        push @objs, $e;
    }
    $self->stash( entries => \@objs );
    $self->render( template => 'publications/all_read' );
}

############################################################################################################

sub landing_years_obj {
    my $self = shift;
    my $year = $self->param('year') || undef;

# if you want to list talks+papers by default on the landing_years page, use the following line
# my $entry_type = $self->param('entry_type') || undef;

# if you want to list ONLY papers by default on the landing_years page, use the following line
    my $entry_type = $self->param('entry_type') || 'paper';

    my $min_year = $self->get_year_of_oldest_entry // $self->current_year;
    my $max_year = $self->current_year;
    # 8 is a month in which we show publications from the next year
    if ( $self->current_month > 8 ) {    # TODO export to config. 
        $max_year++;
    }

    if ( defined $year ) {
        $min_year = $year;
        $max_year = $year;
    }

    my $key = "publications.landing.years." . join("_", @{$self->req->params->pairs} );
    # $html = $self->render_to_string( template => 'publications/all' );
    # $self->app->redis->set($key => $html  );
    my $html = $self->app->redis->get($key);

    if($html){
        $self->render(data => $html);
        return;
    }

    my %hash_dict;
    my %hash_values;
    my @allkeys = ( $min_year .. $max_year );
    @allkeys = reverse @allkeys;

    my @objs_arr;
    my @keys;

    foreach my $yr (@allkeys) {

        # my @objs = get_publications_main($self, undef, $yr, undef, $entry_type, undef, undef, 0, undef);
        my @objs = Fget_publications_main_hashed_args(
            $self,
            {   year       => $yr,
                entry_type => $entry_type,
                visible    => 0,
                hidden     => 0
            }
        );

        # delete the year from the @keys array if the year has 0 papers
        if ( scalar @objs > 0 ) {
            $hash_dict{$yr}   = $yr;
            $hash_values{$yr} = \@objs;
            push @keys, $yr;
        }
    }

    my $switchlink = $self->get_switchlink("types");
    my $navbar_html = $self->get_navbar( \@keys, \%hash_dict, 'years' );

    return $self->display_landing( \%hash_values, \%hash_dict, \@keys,
        $switchlink, $navbar_html );
}
############################################################################################################
sub get_switchlink {
    my $self    = shift;
    my $keyword = shift;
    my $str = '<span class="label label-info" >View: </span>&nbsp;';
    
    if($keyword eq 'years'){
        $str .= '<a class="label label-primary" href="' . $self->url_with('lp') . '">Types</a> ';
        $str .= '<a class="label label-default" href="' . $self->url_with('lyp') . '">Years</a> ';
    }
    elsif($keyword eq 'types'){
        $str .= '<a class="label label-default" href="' . $self->url_with('lp') . '">Types</a> ';
        $str .= '<a class="label label-primary" href="' . $self->url_with('lyp') . '">Years</a> ';
    }
    # $str .= '<br/>';
    return $str;
}
############################################################################################################
sub get_navbar_clear_filter_row {    # only temporary TODO: refactor
    my $self          = shift;
    
    my $tmp_year = $self->req->url->query->param('year');
    $self->req->url->query->remove('year');
    
    my $str = '<span class="label label-info" >Filter: </span>&nbsp;';
    $str .= '<a class="label label-default" href="' . $self->url_with('current') . '">Clear year filter</a> ';

    $self->req->url->query->param( year => $tmp_year )
        if defined $tmp_year and $tmp_year ne "";
    $self->req->url->query->remove('bibtex_type');
    $self->req->url->query->remove('entry_type');

    $str .= '<a class="label label-default" href="' . $self->url_with('current') . '">Clear type filter</a> ';
    $str .= '<br/>';
    return $str;
}
############################################################################################################
sub get_navbar { # only temporary TODO: refactor
    my $self          = shift;
    my $keys          = shift;
    my $hash_dict_ref = shift;
    my $type          = shift // 'years';
    my %hash_dict     = %$hash_dict_ref;
    #say "using get_navbar";

    my $str = $self->get_navbar_clear_filter_row;
    my $tmp_type = $self->req->url->query->param('bibtex_type');
    # NAVBAR

    $str .= '<span class="label label-info" >Years: </span>&nbsp;';

    foreach my $key ( reverse sort @$keys ) {

        $self->req->url->query->param( year => $key );
        $str .= '<a class="label label-default" href="';
        $str .=  $self->url_with( 'current', bibtex_type => $tmp_type );
        $str .=  '">'.$hash_dict{$key}.'</a> ';
    }

    $str;
}

############################################################################################################
sub get_navbar_landing_types {    # only temporary TODO: refactor
    my $self          = shift;
    my $keys          = shift;
    my $hash_dict_ref = shift;
    my $type          = shift // 'years';
    my %hash_dict     = %$hash_dict_ref;

    #say "using get_navbar_landing_types";

    my $str = $self->get_navbar_clear_filter_row;
    $str .= '<span class="label label-info" >Types: </span>&nbsp;';

    foreach my $key ( sort @$keys ) {

        # say "key in keys_with_papers: $key";

        if ( $key eq 'talk' ) {
            $self->req->url->query->remove('bibtex_type');
            $self->req->url->query->param( entry_type => 'talk' );
            $str .= '<a class="label label-default" href="';
            $str .=  $self->url_with( 'current', entry_type => 'talk' );

        }
        else {
            $self->req->url->query->remove('entry_type');
            $self->req->url->query->param( bibtex_type => $key );
            $str .= '<a class="label label-default" href="';
            $str .=  $self->url_with( 'current', entry_type => $key );
        }
        $str .=  '">'.$hash_dict{$key}.'</a> ';
    }
    return $str;
}
############################################################################################################
sub landing_types_obj {    # clean this mess!

    my $self        = shift;
    my $bibtex_type = $self->param('bibtex_type') || undef;
    my $entry_type  = $self->param('entry_type') || undef;

    # key: bibtex_type 
    # value: description of type
    my %bibtex_type_to_label;

    # key: bibtex_type
    # value: ref to array of entry objects
    my %bibtex_type_to_entries;    
                        

    my @keys;
    my @all_keys = get_types_for_landing_page( $self->app->db );

    my @keys_with_papers;

    # shitty ifs

    # include talks only when
    # 1 - entry_type eq talk
    # 2 - both types undefined

    # include only one bibtex type when
    # 1 - bibtex_type defined and entry_type ne talk

    # include all bibtex types but no talks
    #

    # include everything
    # 1 - nothing defined

    # only one bibtex type
    if ( defined $bibtex_type
        and ( !defined $entry_type or $entry_type eq 'paper' ) )
    {
        # no talks
        # single bibtex type
        say "OPTION 1 - only one type";
        my $key = $bibtex_type;

# my @paper_objs = get_publications_main($self, undef, undef, $bibtex_type, $entry_type, undef, undef, 0, undef);
        my @paper_objs = Fget_publications_main_hashed_args(
            $self,
            {   bibtex_type => $bibtex_type,
                entry_type  => $entry_type,
                visible     => 0,
                hidden      => 0
            }
        );
        if ( scalar @paper_objs > 0 ) {
            $bibtex_type_to_label{$key} = get_type_description( $self->app->db, $key );
            $bibtex_type_to_entries{$key} = \@paper_objs;
            push @keys_with_papers, $key;
        }
    }

    # only talks
    elsif ( defined $entry_type and $entry_type eq 'talk' ) {

        say "OPTION 2 - talks only";
        my $key = 'talk';

# my @talk_objs = get_publications_main($self, undef, undef, undef, 'talk', undef, undef, 0, undef);
        my @talk_objs = Fget_publications_main_hashed_args( $self,
            { entry_type => 'talk', visible => 0, hidden => 0 } );
        if ( scalar @talk_objs > 0 ) {
            $bibtex_type_to_label{$key}   = "Talks";
            $bibtex_type_to_entries{$key} = \@talk_objs;
            push @keys_with_papers, $key;
        }
    }

    # all but talks
    elsif (!defined $bibtex_type
        and defined $entry_type
        and $entry_type eq 'paper' )
    {

        say "OPTION 3 - all but talks";
        @keys = @all_keys;

        foreach my $key (@keys) {

# my @paper_objs = get_publications_main($self, undef, undef, $key, 'paper', undef, undef, 0, undef);
            my @paper_objs = Fget_publications_main_hashed_args(
                $self,
                {   bibtex_type => $key,
                    entry_type  => 'paper',
                    visible     => 0,
                    hidden      => 0
                }
            );
            if ( scalar @paper_objs > 0 ) {
                $bibtex_type_to_label{$key}
                    = get_type_description( $self->app->db, $key );
                $bibtex_type_to_entries{$key} = \@paper_objs;
                push @keys_with_papers, $key;
            }
        }
    }

    # all
    elsif ( !defined $entry_type and !defined $bibtex_type ) {

        say "OPTION 4 - all";
        @keys = @all_keys;

        foreach my $key (@keys) {

# my @paper_objs = get_publications_main($self, undef, undef, $key, 'paper', undef, undef, 0, undef);
            my @paper_objs = Fget_publications_main_hashed_args(
                $self,
                {   bibtex_type => $key,
                    entry_type  => 'paper',
                    visible     => 0,
                    hidden      => 0
                }
            );
            if ( scalar @paper_objs > 0 ) {
                $bibtex_type_to_label{$key}
                    = get_type_description( $self->app->db, $key );
                $bibtex_type_to_entries{$key} = \@paper_objs;
                push @keys_with_papers, $key;
            }
        }
        my $key = 'talk';

# my @talk_objs = get_publications_main($self, undef, undef, undef, 'talk', undef, undef, 0, undef);
        my @talk_objs = Fget_publications_main_hashed_args( $self,
            { entry_type => 'talk', visible => 0, hidden => 0 } );
        if ( scalar @talk_objs > 0 ) {
            $bibtex_type_to_label{$key}   = "Talks";
            $bibtex_type_to_entries{$key} = \@talk_objs;
            push @keys_with_papers, $key;
        }
    }
    else {
        say "OPTION 5 - else";
    }


    # not ready yet
    my $switchlink = $self->get_switchlink('years');
    my $navbar_html
        = $self->get_navbar_landing_types( \@keys_with_papers, \%bibtex_type_to_label, 'types' );


    # bibtex_type_to_entries:  key_bibtex_type -> ref_arr_entry_objects
    # bibtex_type_to_label:    key_bibtex_type -> description of the type
    # keys_with_papers: non-empty -> key_bibtex_type
    return $self->display_landing(
        \%bibtex_type_to_entries, \%bibtex_type_to_label, \@keys_with_papers,
        $switchlink,   $navbar_html
    );
}

############################################################################################################
sub display_landing {
    my $self            = shift;
    my $hash_values_ref = shift;
    my $hash_dict_ref   = shift;
    my $keys_ref        = shift;
    my $switchlink      = shift || "";
    my $navbar_html     = shift || "";

    my $navbar     = $self->param('navbar') || 0;
    my $show_title = $self->param('title')  || 0;
    my $show_switch = $self->param('switchlink');

    # if you ommit the switchlink param, assume default = enabled
    # by 0, do not show
    # by 1, do show
    $show_switch = 1 unless defined $show_switch;

    # reset switchlink if show_switch different to 1
    $switchlink = "" unless $show_switch == 1;

    $navbar_html = "" unless $navbar == 1;

    my $permalink = $self->param('permalink');
    my $tag_name = $self->param('tag') || "";

    my $tag_obj = MTag->static_get_by_permalink( $self->app->db, $permalink );
    my $tag_name_for_permalink = -1;
    $tag_name_for_permalink = $tag_obj->{name} if defined $tag_obj;

    $tag_name = $tag_name_for_permalink unless $tag_name_for_permalink == -1;
    $tag_name = $permalink
        if !defined $self->param('tag')
        and $tag_name_for_permalink == -1;
    $tag_name =~ s/_+/_/g
        if defined $tag_name
        and defined $show_title
        and $show_title == 1;
    $tag_name =~ s/_/\ /g
        if defined $tag_name
        and defined $show_title
        and $show_title == 1;

    my $title = "";
    $title .= " Publications "
        if defined $self->param('entry_type')
        and $self->param('entry_type') eq 'paper';
    $title .= " Talks "
        if defined $self->param('entry_type')
        and $self->param('entry_type') eq 'talk';
    $title .= " Publications and talks"
        if !defined $self->param('entry_type');
    $title .= " of team " . $self->param('team')
        if defined $self->param('team');
    $title .= " of author " . $self->param('author')
        if defined $self->param('author');
    $title .= " tagged as " . $tag_name if defined $self->param('tag');
    $title .= " in category " . $tag_name
        if defined $self->param('permalink');
    $title .= " of type " . $self->param('bibtex_type')
        if defined $self->param('bibtex_type');
    $title .= " published in year " . $self->param('year')
        if defined $self->param('year');

    # my $url = $self->req->url;
    # say "scheme ".$url->scheme;
    # say "userinfo ".$url->userinfo;
    # say "host ".$url->host;
    # say "port ".$url->port;
    # say "path ".$url->path;
    # say "query ".$url->query;
    # say "fragment ".$url->fragment;

    # keys = years
    # my @objs = @{ $hash_values{$year} };
    # foreach my $obj (@objs){
    $self->stash(
        hash_values => $hash_values_ref,
        hash_dict   => $hash_dict_ref,
        keys        => $keys_ref,
        navbar      => $navbar_html,
        show_title  => $show_title,
        title       => $title,
        switch_link => $switchlink
    );
    $self->res->headers->header( 'Access-Control-Allow-Origin' => '*' );

    say $self->req->url;
    # putting html result into cache
    my $key = "publications.landing.years." . join("_", @{$self->req->params->pairs} );
    my $html = $self->render_to_string( template => 'publications/landing_obj' );
    # $self->app->redis->set($key => $html);
    $self->render(data => $html);
    
    # $self->render( template => 'publications/landing_obj' );
}

####################################################################################
sub replace_urls_to_file_serving_function {

    ##
    # http://127.0.0.1:3000/publications/download/paper/4/pdf

    my $self = shift;
    my $dbh  = $self->app->db;

    my @all_entries = MEntry->static_all($dbh);

    my $str = "";

    for my $e (@all_entries) {

        my $url_pdf = $self->url_for(
            'download_publication_pdf',
            filetype => 'paper',
            id       => $e->{id}
        )->to_abs;
        my $url_slides = $self->url_for(
            'download_publication',
            filetype => 'slides',
            id       => $e->{id}
        )->to_abs;

        # check if the entry has pdf
        my $pdf_path = $self->get_paper_pdf_path( $e->{id}, "paper" );
        if ( $pdf_path ne 0 ) {    # this means that file exists locally
            if ( $e->bibtex_has_field("pdf") ) {
                add_field_to_bibtex_code( $dbh, $e->{id}, "pdf", "$url_pdf" );
                $str .= "id $e->{id}, PDF: " . $url_pdf;
                $str .= '<br/>';
            }
        }
        my $slides_path = $self->get_paper_pdf_path( $e->{id}, "slides" );
        if ( $slides_path ne 0 ) {    # this means that file exists locally
            if ( $e->bibtex_has_field("slides") ) {
                add_field_to_bibtex_code( $dbh, $e->{id}, "slides",
                    "$url_slides" );
                $str .= "id $e->{id}, SLI: " . $url_slides;
                $str .= '<br/>';
            }
        }
    }

    $self->flash( msg => 'The following urls are now fixed: <br/>' . $str );
    $self->redirect_to( $self->get_referrer );
}
####################################################################################
sub remove_attachment {
    my $self     = shift;
    my $id       = $self->param('id');                     # entry ID
    my $filetype = $self->param('filetype') // 'paper';    # paper, slides
    my $dbh      = $self->app->db;

    my $mentry = MEntry->static_get( $dbh, $id );

    # no check as we want to have the files deleted anyway!

    my $file_path = get_paper_pdf_path( $self, $id, "$filetype" );
    say "file_path $file_path";
    my $num_deleted_files = 0;
    my $msg;
    my $msg_type;

    if ( !defined $file_path or $file_path eq 0 ) {
        $msg
            = "File not found. Cannot remove attachment. Filetype $filetype or entry id $id.";
        $msg_type = 'danger';
    }
    else {    # file exists

        $num_deleted_files = $self->remove_attachment_do( $id, $filetype );
        if ( defined $mentry and $num_deleted_files > 0 ) {
            $mentry->remove_bibtex_fields( $dbh, ['pdf'] )
                if $filetype eq 'paper';
            $mentry->remove_bibtex_fields( $dbh, ['slides'] )
                if $filetype eq 'slides';
            $mentry->regenerate_html( $dbh, 0, $self->app->bst );
            $mentry->save($dbh);
        }

        $msg
            = "There were $num_deleted_files attachments removed for id $id.";
        $msg_type = 'success';
    }

    $self->write_log($msg);
    $self->flash( msg_type => $msg_type, msg => $msg );
    $self->redirect_to( $self->get_referrer );
}
####################################################################################
sub remove_attachment_do {    # refactor this - this is clutter
    my $self     = shift;
    my $id       = shift;
    my $filetype = shift;
    my $dbh      = $self->app->db;

    my $mentry = MEntry->static_get( $dbh, $id );

    my $file_path = get_paper_pdf_path( $self, $id, "$filetype" );
    my $num_deleted_files = 0;

    if ( !defined $mentry or !defined $file_path or $file_path eq 0 ) {
        return 0;
    }

    try {
        unlink $file_path;
        $num_deleted_files = $num_deleted_files + 1;
    }
    catch { };

    # make sure that there is no file
    my $file_path_after_delete
        = get_paper_pdf_path( $self, $id, "$filetype" );
    while ( $file_path_after_delete ne 0 ) {
        try {
            unlink $file_path;
            $num_deleted_files = $num_deleted_files + 1;
        }
        catch { };
        $file_path_after_delete
            = get_paper_pdf_path( $self, $id, "$filetype" );
    }

    return $num_deleted_files;
}
####################################################################################
sub download {
    my $self     = shift;
    my $id       = $self->param('id');                     # entry ID
    my $filetype = $self->param('filetype') || 'paper';    # paper, slides

    # $self->write_log("Requesting download: filetype $filetype, id $id. ");

    my $file_path = $self->get_paper_pdf_path( $id, "$filetype" );
    say "Found paper type $filetype : $file_path";

    if ( !defined $file_path or $file_path eq 0 ) {
        $self->write_log("Unsuccessful download filetype $filetype, id $id.");
        $self->render(
            text =>
                "File not found. Unsuccessful download filetype $filetype, id $id.",
            status => 404
        );
        return;
    }

    my $exists = 0;
    $exists = 1 if -e $file_path;

    if ( $exists == 1 ) {

        # $self->write_log("Serving file $file_path");
        $self->render_file( 'filepath' => $file_path );
    }
    else {
        $self->redirect_to( $self->get_referrer );
    }
}
####################################################################################

sub add_pdf {
    my $self = shift;
    my $id   = $self->param('id');
    my $dbh  = $self->app->db;

    my $mentry = MEntry->static_get( $dbh, $id );
    if ( !defined $mentry ) {
        $self->flash( msg => "There is no entry with id $id" );
        $self->redirect_to( $self->get_referrer );
        return;
    }
    $mentry->populate_from_bib();
    $mentry->generate_html( $self->app->bst );

    $self->stash( mentry => $mentry );
    $self->render( template => 'publications/pdf_upload' );
}
####################################################################################
sub add_pdf_post {
    my $self     = shift;
    my $id       = $self->param('id') || "unknown";
    my $filetype = $self->param('filetype') || undef;
    my $dbh      = $self->app->db;

    my $uploads_directory = $self->config->{upload_dir};
    $uploads_directory
        =~ s!/*$!/!;    # makes sure that there is exactly one / at the end

    my $extension;

    $self->write_log("Saving attachment for paper id $id");

    # Check file size
    if ( $self->req->is_limit_exceeded ) {
        $self->write_log(
            "Saving attachment for paper id $id: limit exceeded!");
        $self->flash(
            message  => "The File is too big and cannot be saved!",
            msg_type => "danger"
        );
        $self->redirect_to( $self->get_referrer );
        return;
    }

    # Process uploaded file
    my $uploaded_file = $self->param('uploaded_file');

    unless ($uploaded_file) {
        $self->flash(
            message  => "File upload unsuccessful!",
            msg_type => "danger"
        );
        $self->write_log(
            "Saving attachment for paper id $id FAILED. Unknown reason");
        $self->redirect_to( $self->get_referrer );
    }

    my $size = $uploaded_file->size;
    if ( $size == 0 ) {
        $self->flash(
            message =>
                "No file was selected or file has 0 bytes! Not saving!",
            msg_type => "danger"
        );
        $self->write_log(
            "Saving attachment for paper id $id FAILED. File size is 0.");
        $self->redirect_to( $self->get_referrer );
    }
    else {
        my $sizeKB = int( $size / 1024 );
        my $name   = $uploaded_file->filename;

        my @dot_arr = split( /\./, $name );
        my $arr_size = scalar @dot_arr;
        $extension = $dot_arr[ $arr_size - 1 ];

        my $fname;
        my $fname_no_ext;
        my $file_path;
        my $bibtex_field;
        my $directory;

        if ( $filetype eq 'paper' ) {
            $fname_no_ext = "paper-" . $id . ".";
            $fname        = $fname_no_ext . $extension;

            $directory    = "papers/";
            $bibtex_field = "pdf";
        }
        elsif ( $filetype eq 'slides' ) {
            $fname_no_ext = "slides-paper-" . $id . ".";
            $fname        = $fname_no_ext . $extension;
            $directory    = "slides/";
            $bibtex_field = "slides";
        }
        else {
            $fname_no_ext = "unknown-" . $id . ".";
            $fname        = $fname_no_ext . $extension;
            $directory    = "unknown/";

            $bibtex_field = "pdf2";
        }
        try {
            path( $uploads_directory . $directory )->mkpath;
        }
        catch {
            warn "Exception: cannot create directory $directory. Msg: $_";
        };

        $file_path = $directory . $fname;

        # remove old file that would match the patterns
        my $old_file = $self->get_paper_pdf_path( $id, "$filetype" );
        say "old_file: $old_file";
        if ( $old_file ne 0 ) {

            # old file exists and must be deleted!
            try {
                unlink $old_file;
                say "Deleting $old_file";
            }
            catch { };
        }

        $uploaded_file->move_to( $uploads_directory . $file_path );

        my $new_file = $self->get_paper_pdf_path( $id, "$filetype" );

        my $file_url = $self->url_for(
            'download_publication',
            filetype => "$filetype",
            id       => $id
        )->to_abs;
        if ( $filetype eq 'paper' ) {    # so that the link looks nicer
            say "Nicing the url for paper";
            say "old file_url $file_url";
            $file_url = $self->url_for(
                'download_publication_pdf',
                filetype => "paper",
                id       => $id
            )->to_abs;
            say "file_url $file_url";
        }

        $self->write_log(
            "Saving attachment for paper id $id under: $file_url");
        add_field_to_bibtex_code( $self->app->db, $id, $bibtex_field,
            "$file_url" );

        my $msg
            = "Successfully uploaded the $sizeKB KB file <em>$name</em> as <strong><em>$filetype</em></strong>.
        The file was renamed to: <em>$fname</em>. URL <a href=\""
            . $file_url . "\">$name</a>";

        my $mentry = MEntry->static_get( $dbh, $id );
        if ( !defined $mentry ) {
            $self->flash( msg => "There is no entry with id $id" );
            $self->redirect_to( $self->get_referrer );
            return;
        }
        $mentry->regenerate_html( $dbh, 0, $self->app->bst );
        $mentry->save($dbh);

        $self->flash( message => $msg );
        $self->redirect_to( $self->get_referrer );
    }
}

####################################################################################
####################################################################################
sub regenerate_html_for_all {
    my $self = shift;
    $self->inactivity_timeout(3000);
    my $dbh = $self->app->db;

    $self->write_log("regenerate_html_for_all is running");

    BibSpace::Functions::FPublications::do_regenerate_html_for_all($dbh, $self->app->bst, 0);

    $self->write_log("regenerate_html_for_all has finished");

    $self->flash(
        msg_type => 'info',
        msg      => 'Regeneration of HTML code finished.'
    );
    my $referrer = $self->get_referrer();
    $self->redirect_to($referrer);
}
####################################################################################

####################################################################################
sub regenerate_html_for_all_force {
    my $self = shift;
    # $self->inactivity_timeout(3000);
    my $dbh = $self->app->db;



    $self->redis->publish("long_running_tasks" => "regenerate_all_force");
    $self->write_log("regenerate_html_for_all FORCE has been enqueued");
    
    # $self->write_log("regenerate_html_for_all_force is running");
    # BibSpace::Functions::FPublications::do_regenerate_html_for_all($dbh, $self->app->bst, 1);
    # $self->write_log("regenerate_html_for_all_force has finished");

    $self->flash(
        msg_type => 'info',
        msg      => 'Regeneration of HTML code has been enqueued and will be executed in background.'
    );
    my $referrer = $self->get_referrer();
    $self->redirect_to($referrer);

}

####################################################################################
sub regenerate_html {
    my $self = shift;
    my $dbh  = $self->app->db;
    my $id   = $self->param('id');

    my $mentry = MEntry->static_get( $dbh, $id );
    if ( !defined $mentry ) {
        $self->flash( msg => "There is no entry with id $id" );
        $self->redirect_to( $self->get_referrer );
        return;
    }
    $mentry->{bst_file} = $self->app->bst;
    $mentry->regenerate_html( $dbh, 1 );
    $mentry->save($dbh);

    $self->redirect_to( $self->get_referrer );
}
####################################################################################

sub delete_sure {
    my $self = shift;
    my $id   = $self->param('id');
    my $dbh  = $self->app->db;

    my $mentry = MEntry->static_get( $dbh, $id );
    if ( !defined $mentry ) {
        $self->flash(
            mgs_type => 'danger',
            msg      => "There is no entry with id $id"
        );
        $self->redirect_to( $self->get_referrer );
        return;
    }

    remove_attachment_do( $self, $id, 'paper' );
    remove_attachment_do( $self, $id, 'slides' );
    $mentry->delete($dbh);

    $self->write_log("Entry id $id has been deleted.");

    $self->redirect_to( $self->get_referrer );
}
####################################################################################
sub show_authors_of_entry {
    my $self = shift;
    my $id   = $self->param('id');
    my $dbh  = $self->app->db;
    $self->write_log("Showing authors of entry id $id");

    my $mentry = MEntry->static_get( $dbh, $id );
    if ( !defined $mentry ) {
        $self->flash( msg => "There is no entry with id $id" );
        $self->redirect_to( $self->get_referrer );
        return;
    }
    my @authors = $mentry->authors($dbh);
    my @teams   = $mentry->teams($dbh);

    $self->stash( entry => $mentry, authors => \@authors, teams => \@teams );
    $self->render( template => 'publications/show_authors' );
}
####################################################################################
sub manage_exceptions {
    my $self = shift;
    my $id   = $self->param('id');
    my $dbh  = $self->app->db;

    my $mentry = MEntry->static_get( $dbh, $id );
    if ( !defined $mentry ) {
        $self->flash( msg => "There is no entry with id $id" );
        $self->redirect_to( $self->get_referrer );
        return;
    }

    my @exceptions = $mentry->exceptions($dbh);
    my @all_teams  = MTeam->static_all($dbh);
    my @teams      = $mentry->teams($dbh);
    my @authors    = $mentry->authors($dbh);

    # cannot use objects as keysdue to stringification!
    my %exceptions_hash = map { $_->{id} => 1 } @exceptions;
    my @unassigned_teams
        = grep { not $exceptions_hash{ $_->{id} } } @all_teams;


    $self->stash(
        entry            => $mentry,
        exceptions       => \@exceptions,
        teams            => \@teams,
        all_teams        => \@all_teams,
        authors          => \@authors,
        unassigned_teams => \@unassigned_teams
    );
    $self->render( template => 'publications/manage_exceptions' );
}
####################################################################################
sub manage_tags {
    my $self = shift;
    my $eid  = $self->param('id');
    my $dbh  = $self->app->db;

    $self->write_log("Manage tags of entry eid $eid");

    my $mentry = MEntry->static_get( $dbh, $eid );
    if ( !defined $mentry ) {
        $self->flash( msg => "There is no entry with id $eid" );
        $self->redirect_to( $self->get_referrer );
        return;
    }

    my @tags      = $mentry->tags($dbh);
    my @tag_types = BibSpace::Functions::TagTypeObj->getAll($dbh);


    $self->stash(
        entry     => $mentry,
        tags      => \@tags,
        tag_types => \@tag_types
    );
    $self->render( template => 'publications/manage_tags' );
}
####################################################################################

sub remove_tag {
    my $self     = shift;
    my $entry_id = $self->param('eid');
    my $tag_id   = $self->param('tid');
    my $dbh      = $self->app->db;

    my $entry = MEntry->static_get( $dbh, $entry_id );
    my $tag = MTag->static_get( $dbh, $tag_id );

    if ( defined $entry and defined $tag ) {
        $entry->remove_tag( $dbh, $tag );
        $self->write_log(
            "Removed tag $tag->{name} from entry id $entry->{id}. ");
    }

    $self->redirect_to( $self->get_referrer );

}
####################################################################################

sub add_tag {
    my $self     = shift;
    my $entry_id = $self->param('eid');
    my $tag_id   = $self->param('tid');
    my $dbh      = $self->app->db;

    my $entry = MEntry->static_get( $dbh, $entry_id );
    my $tag = MTag->static_get( $dbh, $tag_id );

    if ( defined $entry and defined $tag ) {
        $entry->assign_tag( $dbh, $tag );
        $self->write_log("Added tag $tag->{name} to entry id $entry->{id}. ");
    }
    $self->redirect_to( $self->get_referrer );
}
####################################################################################

sub add_exception {
    my $self     = shift;
    my $entry_id = $self->param('eid');
    my $team_id  = $self->param('tid');
    my $dbh      = $self->app->db;

    my $entry = MEntry->static_get( $dbh, $entry_id );
    my $exception = MTeam->static_get( $dbh, $team_id );

    if ( defined $entry and defined $exception ) {
        $entry->assign_exception( $dbh, $exception );
        $self->write_log(
            "Added exception $exception->{name} to entry id $entry->{id}. ");
    }

    $self->redirect_to( $self->get_referrer );

}
####################################################################################

sub remove_exception {
    my $self     = shift;
    my $entry_id = $self->param('eid');
    my $team_id  = $self->param('tid');
    my $dbh      = $self->app->db;

    my $entry = MEntry->static_get( $dbh, $entry_id );
    my $exception = MTeam->static_get( $dbh, $team_id );

    if ( defined $entry and defined $exception ) {
        $entry->remove_exception( $dbh, $exception );
        $self->write_log(
            "Added exception $exception->{name} to entry id $entry->{id}. ");
    }

    $self->redirect_to( $self->get_referrer );

}

####################################################################################
sub get_adding_editing_message_for_error_code {
    my $self        = shift;
    my $exit_code   = shift;
    my $existing_id = shift || -1;

    # -1 You have bibtex errors! Not saving!";
    # -2 Displaying preview';
    # 0 Entry added successfully';
    # 1 Entry updated successfully';
    # 2 The proposed key is OK.
    # 3 Proposed key exists already - HTML message

    if ( $exit_code eq 'ERR_BIBTEX' ) {
        return
            "You have bibtex errors! No changes were written to the database.";
    }
    elsif ( $exit_code eq 'PREVIEW' ) {
        return 'Displaying preview. No changes were written to the database.';
    }
    elsif ( $exit_code eq 'ADD_OK' ) {
        return 'Entry added successfully. Switched to editing mode.';
    }
    elsif ( $exit_code eq 'EDIT_OK' ) {
        return 'Entry updated successfully.';
    }
    elsif ( $exit_code eq 'KEY_OK' ) {
        return
            'The proposed key is OK. You may continue with your edits. No changes were written to the database.';
    }
    elsif ( $exit_code eq 'KEY_TAKEN' ) {
        return
            'The proposed key exists already in DB under ID <button class="btn btn-danger btn-xs" tooltip="Entry ID"> <span class="glyphicon glyphicon-barcode"></span> '
            . $existing_id
            . '</button>.
                  <br>
                  <a class="btn btn-info btn-xs" href="'
            . $self->url_for( 'edit_publication', id => $existing_id )
            . '" target="_blank"><span class="glyphicon glyphicon-search"></span>Show me the existing entry ID '
            . $existing_id
            . ' in a new window</a>
                  <br>
                  Entry has not been saved. Please pick another BibTeX key. No changes were written to the database.';
    }
    elsif ( defined $exit_code and $exit_code ne '' ) {
        return "Unknown exit code: $exit_code";
    }

}


####################################################################################
sub publications_add_get {
    say "CALL: publications_add_get ";
    my $self = shift;
    $self->write_log("Adding publication");
    my $dbh = $self->app->db;


    my $msg = "<strong>Adding mode</strong> You operate on an unsaved entry!";
    my $e_dummy = MEntry->new();
    $e_dummy->{id} = -1;
    my $bib = '@article{key' . get_current_year() . ',
      author = {Johny Example},
      title = {{Selected aspects of some methods}},
      year = {' . get_current_year() . '},
      month = {' . $mons{ get_current_month() } . '},
      day = {1--31},
  }';
    $e_dummy->{bib}    = $bib;
    $e_dummy->{hidden} = 0;      # new papers are not hidden by default
    $e_dummy->populate_from_bib();
    $e_dummy->generate_html( $self->app->bst );

    $self->stash( mentry => $e_dummy, msg => $msg );
    $self->render( template => 'publications/edit_entry' );
}
####################################################################################
sub publications_add_post {
    say "CALL: publications_add_post ";
    my $self            = shift;
    my $new_bib         = $self->param('new_bib');
    my $param_prev      = $self->param('preview');
    my $param_save      = $self->param('save');
    my $param_check_key = $self->param('check_key');
    my $dbh             = $self->app->db;

    my $action = 'default';
    $action = 'save'      if $param_save;         # user clicks save
    $action = 'preview'   if $param_prev;         # user clicks preview
    $action = 'check_key' if $param_check_key;    # user clicks check key

    $self->write_log("Adding publication. Action: > $action <.");

    $new_bib =~ s/^\s+|\s+$//g;
    $new_bib =~ s/^\t//g;

    my ( $mentry, $status_code_str, $existing_id, $added_under_id )
        = Fhandle_add_edit_publication( $dbh, $new_bib, -1, $action,
        $self->app->bst );
    my $adding_msg
        = get_adding_editing_message_for_error_code( $self, $status_code_str,
        $existing_id );

    $self->write_log(
        "Adding publication. Action: > $action <. Status code: $status_code_str."
    );

    # status_code_strings
    # -2 => PREVIEW
    # -1 => ERR_BIBTEX
    # 0 => ADD_OK
    # 1 => EDIT_OK
    # 2 => KEY_OK
    # 3 => KEY_TAKEN
    my $bibtex_warnings = FprintBibtexWarnings( $mentry->{warnings} );
    my $msg             = $adding_msg . $bibtex_warnings;
    my $msg_type        = 'success';
    $msg_type = 'warning' if $bibtex_warnings =~ m/Warning/;
    $msg_type = 'danger'
        if $status_code_str eq 'ERR_BIBTEX'
        or $status_code_str eq 'KEY_TAKEN'
        or $bibtex_warnings =~ m/Error/;

    $self->stash( mentry => $mentry, msg => $msg, msg_type => $msg_type );

    if ( $status_code_str eq 'ADD_OK' ) {
        $self->flash( msg => $msg, msg_type => $msg_type );
        $self->redirect_to(
            $self->url_for( 'edit_publication', id => $added_under_id ) );
    }
    else {
        $self->render( template => 'publications/edit_entry' );
    }
}
####################################################################################
sub publications_edit_get {
    my $self = shift;
    my $id = $self->param('id') || -1;

    $self->write_log("Editing publication entry id $id");

    my $dbh = $self->app->db;


    my $mentry = MEntry->static_get( $dbh, $id );
    if ( !defined $mentry ) {
        $self->flash( msg => "There is no entry with id $id" );
        $self->redirect_to( $self->get_referrer );
        return;
    }
    $mentry->populate_from_bib();
    $mentry->generate_html( $self->app->bst );

    $self->stash( mentry => $mentry );
    $self->render( template => 'publications/edit_entry' );
}
####################################################################################
sub publications_edit_post {
    say "CALL: publications_edit_post";
    my $self            = shift;
    my $id              = $self->param('id') || -1;
    my $new_bib         = $self->param('new_bib');
    my $param_prev      = $self->param('preview');
    my $param_save      = $self->param('save');
    my $param_check_key = my $dbh = $self->app->db;

    my $action = 'save';    # user clicks save
    $action = 'preview' if $self->param('preview');    # user clicks preview
    $action = 'check_key'
        if $self->param('check_key');                  # user clicks check key

    $self->write_log("Editing publication id $id. Action: > $action <.");

    $new_bib =~ s/^\s+|\s+$//g;
    $new_bib =~ s/^\t//g;

    my ( $mentry, $status_code_str, $existing_id, $added_under_id )
        = Fhandle_add_edit_publication( $dbh, $new_bib, $id, $action,
        $self->app->bst );
    my $adding_msg
        = get_adding_editing_message_for_error_code( $self, $status_code_str,
        $existing_id );


    $self->write_log(
        "Editing publication id $id. Action: > $action <. Status code: $status_code_str."
    );

    # status_code_strings
    # -2 => PREVIEW
    # -1 => ERR_BIBTEX
    # 0 => ADD_OK
    # 1 => EDIT_OK
    # 2 => KEY_OK
    # 3 => KEY_TAKEN

    my $bibtex_warnings = FprintBibtexWarnings( $mentry->{warnings} );
    my $msg             = $adding_msg . $bibtex_warnings;
    my $msg_type        = 'success';
    $msg_type = 'warning' if $bibtex_warnings =~ m/Warning/;
    $msg_type = 'danger'
        if $status_code_str eq 'ERR_BIBTEX'
        or $status_code_str eq 'KEY_TAKEN'
        or $bibtex_warnings =~ m/Error/;

    $self->stash( mentry => $mentry, msg => $msg, msg_type => $msg_type );
    $self->render( template => 'publications/edit_entry' );
}
####################################################################################
sub clean_ugly_bibtex {
    my $self = shift;
    my $dbh  = $self->app->db;

    $self->write_log("Cleaning ugly bibtex fields for all entries");

    Fclean_ugly_bibtex_fields_for_all_entries($dbh);

    $self->flash(
        msg_type => 'info',
        msg      => 'All entries have now their Bibtex cleaned.'
    );

    $self->redirect_to( $self->get_referrer );
}
####################################################################################
sub get_paper_pdf_path {
    my $self = shift;
    my $id   = shift;
    my $type = shift || "paper";

    my $upload_dir = $self->config->{upload_dir};
    $upload_dir
        =~ s!/*$!/!;    # makes sure that there is exactly one / at the end

    my $filequery = "";
    $filequery .= "paper-" . $id . "."        if $type eq "paper";
    $filequery .= "slides-paper-" . $id . "." if $type eq "slides";

    my $directory = $upload_dir;
    $directory .= "papers/" if $type eq "paper";
    $directory .= "slides/" if $type eq "slides";
    my $filename = undef;

    # make sure that the directories exist
    try {
        path($directory)->mkpath;
    }
    catch {
        warn "Exception: cannot create directory $directory. Msg: $_";
    };

    opendir( DIR, $directory )
        or die "Cannot open directory $directory :" . $!;
    while ( my $file = readdir(DIR) ) {

        # Use a regular expression to ignore files beginning with a period
        next if ( $file =~ m/^\./ );
        if ( $file =~ /^$filequery.*/ ) {    # filequery contains the dot!
            say "get_paper_pdf_path MATCH $file $filequery";
            $filename = $file;
        }
    }
    closedir(DIR);
    if ( !defined $filename ) {
        return 0;
    }

    my $file_path = $directory . $filename;
    return $file_path;
}
####################################################################################
1;
