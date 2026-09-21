# eggdrop-pisg.tcl - pisg for eggdrop: !pisgstats, and profiles people edit themselves.
#
# Based on pisg.tcl by HM2K / Arganan (the !pisgstats command). The profile commands are new
# in pisg 1.0a. People set their own sex, picture, link and merge their nicks in chat; the
# bot writes them to users.cfg, which pisg reads through  <include="/path/to/users.cfg">  on
# its next run. Nothing else is needed: no web page, no database.
#
# Commands (in the channel with !, or in a private message without it):
#   pisghelp [command]     what the commands do
#   pisginfo <name> [male|female] [picture-url] [link]      set your profile
#   pisgmerge <name>       count the nick you are using now as <name>
#   pisgunmerge <nick>     stop counting <nick> as yours
#   pisgshow [name]        show a profile
#   pisgdel                delete your own profile
#   pisgdeluser <name>     bot masters only: delete anybody's profile
#   pisgstats              give the address of the stats page (anybody)
#
# Who is who: the bot only edits a profile for someone it can identify, by the services account
# (eggdrop's getaccount, or the account.users.undernet.org host X gives to people logged in
# with +x). A profile belongs to the account, not the nick, so changing nick is fine. You can
# only claim the nick you are using right now, so nobody can take somebody else's name.

namespace eval pisg {
    variable version   "1.0a"

    # ---- settings -------------------------------------------------------------------------
    # Change these to match your setup, or keep your own values in pisg.local.tcl next to this file
    # (see below), so an update of this script never overwrites them.
    variable exe        "/path/to/pisg/pisg"                ;# the pisg script
    variable url        "https://example.org/stats/"        ;# folder the stats pages are in (with the closing /)
    variable chan       "#yourchannel"
    variable outdir     "/path/to/pisg/output"              ;# where pisg writes the pages (for the "updated" age)
    variable adminflags "m"                ;# who may use pisgdeluser
    variable usersfile  "/path/to/pisg/users.cfg"           ;# written by the bot, read by pisg
    variable maincfg    "/path/to/pisg/pisg.cfg"            ;# your hand-written <user> lines are protected
    variable trigger    "!"
    variable accounthost {^[^@]*@([^.@]+)\.users\.undernet\.org$}   ;# Undernet: the host X gives to a logged-in +x user. Other networks: see getaccount
    variable maxaliases 20
    variable minsecs    2                  ;# seconds between two changes by the same account
    variable maxperhour 30                 ;# changes per hour per account
    variable autorun    0                  ;# 1: run pisg from a timer (cron normally does)
    variable autorunmin 180

    # Your own settings: a file called pisg.local.tcl in the same folder is read here, after the
    # defaults above. It only needs lines such as   set ::pisg::url "https://example.org/stats/"
    set localsettings [file join [file dirname [info script]] pisg.local.tcl]
    if {[file exists $localsettings]} { source $localsettings }

    variable marker "# ---- managed by eggdrop-pisg.tcl: do not edit below this line, the bot rewrites it ----"
    variable hist;   array set hist {}

    # ---- checks ---------------------------------------------------------------------------
    proc valid_nick {n} { return [regexp {^[A-Za-z_\[\]\\`^{|}][A-Za-z0-9_\-\[\]\\`^{|}]{0,29}$} $n] }

    # a web address that is safe to put in a page and in a config line
    proc valid_url {u} {
        if {[string length $u] > 300} { return 0 }
        if {![regexp {^https://([A-Za-z0-9.-]+)(:[0-9]+)?(/[^\s"'<>\\]*)?$} $u -> host]} { return 0 }
        # a real domain name: labels of letters, digits and inner hyphens, ending in a letters-only TLD.
        # That also rules out localhost, numeric addresses, ".org", "a..b" and "-x.com".
        if {![regexp {^([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$} $host]} { return 0 }
        return 1
    }
    proc valid_image {u} {
        return [expr {[valid_url $u] && [regexp -nocase {^[^?#]*\.(png|jpe?g|gif|webp)([?#].*)?$} $u]}]
    }
    proc valid_email {e} {
        return [regexp {^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9.-]{1,200}\.[A-Za-z]{2,}$} $e]
    }
    proc clean {s} { regsub -all {[\x00-\x1f\x7f]} $s " " s; return $s }     ;# no control codes in what we send

    # ---- who is asking --------------------------------------------------------------------
    # The services account name of the person, or "" when they are not identified.
    proc account {nick uhost} {
        variable accounthost
        if {[llength [info commands getaccount]] && ![catch {getaccount $nick} a]} {
            if {$a ne "" && $a ne "*"} { return [string tolower $a] }
        }
        if {[regexp $accounthost $uhost -> acct]} { return [string tolower $acct] }
        return ""
    }
    proc login_help {} {
        return "I can only change a profile for someone I can identify. Log in to X and hide your host: /msg x@channels.undernet.org login <username> <password> then /mode <yournick> +x , then try again."
    }

    # ---- the users file -------------------------------------------------------------------
    # An entry is a dict: name aliases sex pic link owner.
    proc attr {line key} {
        if {[regexp "\\m$key=(\[\"'\])(.+?)\\1" $line -> q v]} { return $v }
        return ""
    }
    proc read_file {path} {
        if {![file exists $path]} { return "" }
        set f [open $path r]; fconfigure $f -encoding utf-8
        set d [read $f]; close $f
        return $d
    }
    # -> {manual-text entries}: the part above the marker is yours and is kept as it is
    proc load {} {
        variable usersfile; variable marker
        set data [read_file $usersfile]
        set i [string first $marker $data]
        if {$i < 0} { set manual $data; set managed "" } else {
            set manual [string range $data 0 [expr {$i - 1}]]
            set managed [string range $data [expr {$i + [string length $marker]}] end]
        }
        set entries {}
        foreach line [split $managed "\n"] {
            if {![string match "<user *" [string trim $line]]} { continue }
            set name [attr $line nick]
            if {$name eq ""} { continue }
            # aliases are split with regexp, never with list commands: nicks may contain { } [ ] \ which are special in Tcl lists
            lappend entries [dict create name $name aliases [regexp -all -inline {\S+} [attr $line alias]] sex [attr $line sex] \
                pic [attr $line pic] link [attr $line link] owner [attr $line owner]]
        }
        return [list $manual $entries]
    }
    proc save {manual entries} {
        variable usersfile; variable marker
        set out [string trimright $manual "\n"]
        if {$out eq ""} { set out "# pisg users. Lines above the marker are yours; the bot manages the ones below." }
        append out "\n\n$marker\n"
        foreach e [lsort -command {apply {{a b} {string compare -nocase [dict get $a name] [dict get $b name]}}} $entries] {
            set l "<user nick=\"[dict get $e name]\""
            if {[llength [dict get $e aliases]]} { append l " alias=\"[join [dict get $e aliases] { }]\"" }
            foreach {k a} {pic pic sex sex link link} {
                if {[dict get $e $k] ne ""} { append l " $a=\"[dict get $e $k]\"" }
            }
            append l " owner=\"[dict get $e owner]\">"
            append out "$l\n"
        }
        set tmp "$usersfile.tmp[pid]"
        set f [open $tmp w 0644]; fconfigure $f -encoding utf-8
        puts -nonewline $f $out; close $f
        file rename -force $tmp $usersfile                        ;# atomic: pisg never reads half a file
    }

    # every nick or alias somebody already holds: your hand-written lines, and everyone's entries
    proc reserved {manual entries} {
        variable maincfg
        set r [dict create]
        foreach text [list $manual [read_file $maincfg]] {
            foreach line [split $text "\n"] {
                set t [string trim $line]
                if {[string match "#*" $t] || ![string match "*<user*" $t]} { continue }
                set n [attr $line nick]
                if {$n ne ""} { dict set r [string tolower $n] manual }
                foreach a [regexp -all -inline {\S+} [attr $line alias]] { dict set r [string tolower $a] manual }
            }
        }
        foreach e $entries {
            dict set r [string tolower [dict get $e name]] [dict get $e owner]
            foreach a [dict get $e aliases] { dict set r [string tolower $a] [dict get $e owner] }
        }
        return $r
    }
    proc find_owner {entries acct} {
        set i 0
        foreach e $entries { if {[dict get $e owner] eq $acct} { return $i }; incr i }
        return -1
    }
    proc find_name {entries name} {
        set i 0
        foreach e $entries { if {[string equal -nocase [dict get $e name] $name]} { return $i }; incr i }
        return -1
    }
    proc sex_word {s} { switch $s { m {return male} f {return female} default {return "not set"} } }
    proc describe {e} {
        set s "[dict get $e name]: [sex_word [dict get $e sex]]"
        if {[dict get $e pic]  ne ""} { append s ", picture [dict get $e pic]" }
        if {[dict get $e link] ne ""} { append s ", link [dict get $e link]" }
        if {[llength [dict get $e aliases]]} { append s ", also counted as: [join [dict get $e aliases] {, }]" }
        return $s
    }

    # ---- rate limit ------------------------------------------------------------------------
    proc allowed {acct} {
        variable hist; variable minsecs; variable maxperhour
        set now [clock seconds]
        set recent {}
        if {[info exists hist($acct)]} { foreach t $hist($acct) { if {$now - $t < 3600} { lappend recent $t } } }
        if {[llength $recent] && $now - [lindex $recent end] < $minsecs} { set hist($acct) $recent; return 0 }
        if {[llength $recent] >= $maxperhour} { set hist($acct) $recent; return 0 }
        lappend recent $now; set hist($acct) $recent
        return 1
    }

    # ---- the commands: each returns the lines to say back --------------------------------------
    proc parse_profile {words} {
        # -> {ok sex pic link error}
        set sex ""; set pic ""; set link ""
        foreach w $words {
            if {[regexp {^(sex|pic|link|mail)=(.*)$} $w -> k v]} {
                if {$k eq "sex"} { set w $v } elseif {$k eq "pic"} { set pic $v; continue } else { set link $v; continue }
            }
            switch -nocase -- $w {
                m - male   { set sex m; continue }
                f - female { set sex f; continue }
            }
            if {[valid_image $w] && $pic eq ""} { set pic $w } elseif {[valid_url $w] && $link eq ""} { set link $w } \
            elseif {[valid_email $w] && $link eq ""} { set link $w } else {
                return [list 0 "" "" "" "I don't understand '[clean $w]': give male or female, a picture address (https, ending in .png .jpg .gif or .webp) and/or a link (https or an e-mail address)."]
            }
        }
        if {$pic ne "" && ![valid_image $pic]} { return [list 0 "" "" "" "That picture address is not valid: it must be https and end in .png, .jpg, .gif or .webp."] }
        if {$link ne "" && ![valid_url $link] && ![valid_email $link]} { return [list 0 "" "" "" "That link is not valid: use an https address or an e-mail address."] }
        return [list 1 $sex $pic $link ""]
    }

    proc cmd_info {nick acct isadmin arg} {
        set words [regexp -all -inline {\S+} $arg]
        if {[llength $words] < 1} { return [list "Usage: pisginfo <name> \[male|female\] \[picture-url\] \[link\]   (ask: pisghelp pisginfo)"] }
        if {$acct eq ""} { return [list [login_help]] }
        set name [lindex $words 0]
        if {![valid_nick $name]} { return [list "'[clean $name]' is not a valid nick."] }
        lassign [parse_profile [lrange $words 1 end]] ok sex pic link err
        if {!$ok} { return [list $err] }
        if {$sex eq "" && $pic eq "" && $link eq ""} { return [list "Nothing to set. Give male or female, a picture and/or a link (ask: pisghelp pisginfo)."] }
        lassign [load] manual entries
        set i [find_owner $entries $acct]
        if {$i >= 0} {
            set e [lindex $entries $i]
            if {![string equal -nocase [dict get $e name] $name]} {
                return [list "You already have a profile named [dict get $e name]. Use that name, or delete it first with pisgdel."]
            }
        } else {
            if {![string equal -nocase $name $::pisg::currentnick]} {
                return [list "You can only create a profile for the nick you are using now ($::pisg::currentnick). Change to $name first, or use your current nick."]
            }
            set res [reserved $manual $entries]
            if {[dict exists $res [string tolower $name]]} {
                return [list "$name is already taken by another profile."]
            }
            set e [dict create name $name aliases "" sex "" pic "" link "" owner $acct]
            set entries [linsert $entries end $e]; set i [expr {[llength $entries] - 1}]
        }
        if {$sex  ne ""} { dict set e sex  $sex }
        if {$pic  ne ""} { dict set e pic  $pic }
        if {$link ne ""} { dict set e link $link }
        set entries [lreplace $entries $i $i $e]
        save $manual $entries
        return [list "Saved. [describe $e]. It shows on the next stats update."]
    }

    proc cmd_merge {nick acct isadmin arg} {
        set name [lindex [regexp -all -inline {\S+} $arg] 0]
        if {$name eq ""} { return [list "Usage: pisgmerge <name>: counts the nick you are using now ($nick) as <name>. (ask: pisghelp pisgmerge)"] }
        if {$acct eq ""} { return [list [login_help]] }
        if {![valid_nick $name]} { return [list "'[clean $name]' is not a valid nick."] }
        lassign [load] manual entries
        set i [find_owner $entries $acct]
        if {$i < 0 || ![string equal -nocase [dict get [lindex $entries $i] name] $name]} {
            return [list "You don't have a profile called $name. Create it first, from your main nick: pisginfo $name male|female"]
        }
        set e [lindex $entries $i]
        if {[string equal -nocase $nick $name]} { return [list "You are already $name."] }
        if {[lsearch -nocase [dict get $e aliases] $nick] >= 0} { return [list "$nick is already counted as $name."] }
        set res [reserved $manual $entries]
        if {[dict exists $res [string tolower $nick]]} { return [list "$nick is already used by another profile, so I can't add it."] }
        if {[llength [dict get $e aliases]] >= $::pisg::maxaliases} { return [list "That is the maximum of $::pisg::maxaliases aliases."] }
        dict lappend e aliases $nick
        set entries [lreplace $entries $i $i $e]
        save $manual $entries
        return [list "Done: $nick now counts as $name. It shows on the next stats update."]
    }

    proc cmd_unmerge {nick acct isadmin arg} {
        set a [lindex [regexp -all -inline {\S+} $arg] 0]
        if {$a eq ""} { return [list "Usage: pisgunmerge <nick>: stops counting <nick> as yours."] }
        if {$acct eq ""} { return [list [login_help]] }
        lassign [load] manual entries
        set i [find_owner $entries $acct]
        if {$i < 0} { return [list "You don't have a profile."] }
        set e [lindex $entries $i]
        set k [lsearch -nocase [dict get $e aliases] $a]
        if {$k < 0} { return [list "$a is not one of your aliases."] }
        dict set e aliases [lreplace [dict get $e aliases] $k $k]
        set entries [lreplace $entries $i $i $e]
        save $manual $entries
        return [list "Done: $a no longer counts as [dict get $e name]."]
    }

    proc cmd_show {nick acct isadmin arg} {
        set name [lindex [regexp -all -inline {\S+} $arg] 0]
        lassign [load] manual entries
        if {$name eq ""} {
            set i [expr {$acct ne "" ? [find_owner $entries $acct] : -1}]
            if {$i < 0} { set i [find_name $entries $nick] }
            if {$i < 0} { return [list "You have no profile yet. Make one with: pisginfo $nick male|female <picture-url> <link>"] }
        } else {
            set i [find_name $entries $name]
            if {$i < 0} {
                set res [reserved $manual {}]
                if {[dict exists $res [string tolower $name]]} { return [list "$name has a profile set by hand in the pisg config."] }
                return [list "No profile for [clean $name]."]
            }
        }
        return [list [describe [lindex $entries $i]]]
    }

    proc cmd_del {nick acct isadmin arg} {
        if {$acct eq ""} { return [list [login_help]] }
        lassign [load] manual entries
        set i [find_owner $entries $acct]
        if {$i < 0} { return [list "You don't have a profile."] }
        set name [dict get [lindex $entries $i] name]
        save $manual [lreplace $entries $i $i]
        return [list "Deleted the profile $name."]
    }

    proc cmd_deluser {nick acct isadmin arg} {
        if {!$isadmin} { return [list "Only bot masters can delete other people's profiles. To delete your own, use pisgdel."] }
        set name [lindex [regexp -all -inline {\S+} $arg] 0]
        if {$name eq ""} { return [list "Usage: pisgdeluser <name>"] }
        lassign [load] manual entries
        set i [find_name $entries $name]
        if {$i < 0} {
            set res [reserved $manual {}]
            if {[dict exists $res [string tolower $name]]} { return [list "$name is written by hand in a config file. Edit that file to remove it."] }
            return [list "No profile for [clean $name]."]
        }
        set d [lindex $entries $i]
        save $manual [lreplace $entries $i $i]
        return [list "Deleted the profile [dict get $d name] (account [dict get $d owner])."]
    }

    proc help_text {} {
        return {
            pisghelp {"pisghelp [command]: what the commands do. Try: pisghelp pisginfo"}
            pisginfo {"pisginfo <name> [male|female] [picture-url] [link]: set your profile on the stats page. <name> is the nick you are using now. Any of the parts can be given later, alone. Picture: https address ending in .png .jpg .gif or .webp. Link: an https address or an e-mail address."
                      "Example: pisginfo Alice male https://example.org/me.png https://example.org"}
            pisgmerge {"pisgmerge <name>: counts the nick you are using now as <name>, so Alice_ and Alice- are the same person as Alice. Do it once from each nick, after creating <name> with pisginfo."}
            pisgunmerge {"pisgunmerge <nick>: stops counting <nick> as yours."}
            pisgshow {"pisgshow [name]: shows a profile. Without a name, shows yours."}
            pisgdel {"pisgdel: deletes your own profile, so your picture, link and merged nicks are removed from the stats."}
            pisgdeluser {"pisgdeluser <name>: bot masters only: deletes anybody's profile."}
            pisgstats {"pisgstats: regenerates the stats now and gives the address (friends of the bot only)."}
        }
    }
    proc cmd_help {nick acct isadmin arg} {
        variable trigger
        set h [help_text]
        set c [string tolower [string trimleft [lindex [regexp -all -inline {\S+} $arg] 0] $trigger]]
        if {$c ne "" && ![string match "pisg*" $c]} { set c "pisg$c" }
        if {$c eq ""} {
            return [list "Commands: pisginfo, pisgmerge, pisgunmerge, pisgshow, pisgdel, pisgdeluser, pisgstats. Use them in the channel with $trigger in front, or in a private message without it. For details: ${trigger}pisghelp <command>, e.g. ${trigger}pisghelp pisgshow." \
                "To change a profile you must be logged in to X with +x, so I can tell who you are."]
        }
        if {![dict exists $h $c]} { return [list "I don't know a command called '[clean $c]'. Try ${trigger}pisghelp."] }
        return [dict get $h $c]
    }

    # ---- eggdrop glue -----------------------------------------------------------------------
    variable currentnick ""
    proc say {nick lines} {
        foreach l $lines {
            set l [clean $l]
            while {[string length $l] > 380} {                 ;# IRC lines are limited to 512 bytes in all
                set cut [string last " " $l 380]; if {$cut < 100} { set cut 380 }
                putserv "NOTICE $nick :[string range $l 0 $cut]"
                set l [string trimleft [string range $l [expr {$cut + 1}] end]]
            }
            putserv "NOTICE $nick :$l"
        }
    }
    proc dispatch {cmd nick uhost hand arg} {
        variable currentnick
        set currentnick $nick
        set acct [account $nick $uhost]
        set edits {info merge unmerge del deluser}
        if {[lsearch $edits $cmd] >= 0 && $acct ne "" && ![allowed $acct]} {
            say $nick [list "Slow down a little, then try again."]; return
        }
        set isadmin [expr {$hand ne "*" && [matchattr $hand $::pisg::adminflags]}]
        if {[catch {cmd_$cmd $nick $acct $isadmin $arg} lines]} {
            putlog "pisg: error in $cmd for $nick: $lines"
            set lines [list "Something went wrong on my side, sorry. The bot owner can see it in the log."]
        } elseif {[lsearch $edits $cmd] >= 0 && [regexp {^(Saved|Done|Deleted)} [lindex $lines 0]]} {
            putlog "pisg: $cmd by $nick (account $acct): [lindex $lines 0]"
        }
        say $nick $lines
    }
    foreach c {help info merge unmerge show del deluser} {
        proc pub_$c {nick uhost hand chan arg} "dispatch $c \$nick \$uhost \$hand \$arg"
        proc msg_$c {nick uhost hand arg}      "dispatch $c \$nick \$uhost \$hand \$arg"
        bind pub - "${trigger}pisg$c"  ::pisg::pub_$c
        bind msg - "pisg$c"            ::pisg::msg_$c
    }

    # The original command, kept: regenerate the stats now and give the link.
    # Open to everyone: it only points at the page the hourly cron job keeps fresh (it used to run
    # pisg inside the bot, which froze the bot for the length of the run and stayed silent
    # for anyone without the f flag).
    proc pub_stats {nick host hand chan arg} {
        variable url; variable outdir
        set page "[string tolower [string trimleft $chan #]].html"
        set age ""
        if {![catch {file mtime "$outdir/$page"} t]} {
            set m [expr {([clock seconds] - $t) / 60}]
            set age [expr {$m < 90 ? " (updated $m min ago)" : " (updated [expr {$m / 60}] h ago)"}]
        }
        puthelp "PRIVMSG $chan :Stats: ${url}${page}$age"
    }
    bind pub - "${trigger}pisgstats" ::pisg::pub_stats

    # Optional timer (off by default: the hourly cron job already runs pisg).
    proc timer_run {} {
        variable exe; variable autorunmin
        catch {exec $exe}
        timer $autorunmin ::pisg::timer_run
    }
    if {$autorun && ![info exists ::pisg_timer_set]} { set ::pisg_timer_set 1; timer 2 ::pisg::timer_run }
}

putlog "eggdrop-pisg.tcl $::pisg::version loaded (profiles: !pisghelp)"
