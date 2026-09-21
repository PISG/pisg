# Tests for eggdrop-pisg.tcl, run outside eggdrop with a mock of the eggdrop commands:
#     tclsh8.6 scripts/eggdrop-pisg-test.tcl
# They never touch a real users file: everything happens in a temporary folder.

set here [file dirname [file normalize [info script]]]
set tmp [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] "pisgtest.[pid]"]
file mkdir $tmp

# ---- a mock of the eggdrop commands the script uses ---------------------------------------
set ::sent {}; set ::binds {}; set ::logs {}; set ::acctreply {}
proc bind {type flags cmd proc} { lappend ::binds [list $type $flags $cmd $proc] }
proc putserv {line} { lappend ::sent $line }
proc puthelp {line} { lappend ::sent $line }
proc putlog {line}  { lappend ::logs $line }
proc timer {args} {}
proc matchattr {hand flags} { return [expr {$hand eq "boss"}] }
proc getaccount {nick} { if {[dict exists $::acctreply $nick]} { return [dict get $::acctreply $nick] } else { return "" } }

source [file join $here eggdrop-pisg.tcl]
set pisg::usersfile [file join $tmp users.cfg]
set pisg::maincfg   [file join $tmp pisg.cfg]
set pisg::minsecs 0

set fails 0; set passes 0
proc ok {cond msg} { if {$cond} { incr ::passes } else { incr ::fails; puts "  FAIL: $msg" } }
# run a command as if typed in a private message; returns what the bot said (NOTICE texts)
proc say {cmd nick uhost hand arg} {
    set ::sent {}
    pisg::dispatch $cmd $nick $uhost $hand $arg
    set out {}
    foreach l $::sent { regexp {^NOTICE \S+ :(.*)$} $l -> t; lappend out $t }
    return $out
}
proc first {lines} { return [lindex $lines 0] }
proc filetext {} { return [pisg::read_file $pisg::usersfile] }
proc reset {} { file delete -force $pisg::usersfile; file delete -force $pisg::maincfg; array unset pisg::hist; set ::acctreply {} }

set ALICE  "~u@alice.users.undernet.org"
set BOB  "~b@bob.users.undernet.org"
set ANON "~x@dsl-123.example.net"

puts "1. identity"
reset
ok [string match "*Log in to X*" [first [say info Alice $ANON * "Alice male"]]] "someone not logged in to X gets login instructions"
ok [expr {[pisg::account Alice $ALICE] eq "alice"}] "account name from the host"
ok [expr {[pisg::account Alice $ANON] eq ""}] "no account for an ordinary host"
set ::acctreply [dict create Alice "AliceAcct"]
ok [expr {[pisg::account Alice $ANON] eq "aliceacct"}] "getaccount is used first, lower-cased"
set ::acctreply [dict create Alice "*"]
ok [expr {[pisg::account Alice $ALICE] eq "alice"}] "getaccount '*' (not logged in) falls back to the host"
set ::acctreply {}
ok [string match "*Log in to X*" [first [say info Alice $ANON * "Alice male"]]] "still no login: still no edit"
ok [expr {![file exists $pisg::usersfile]}] "nothing written for an unidentified user"

puts "2. creating and updating a profile"
reset
set r [first [say info Alice $ALICE * "Alice male https://example.org/me.png https://example.org"]]
ok [string match "Saved*" $r] "profile saved: $r"
set t [filetext]
ok [string match {*<user nick="Alice" pic="https://example.org/me.png" sex="m" link="https://example.org" owner="alice">*} $t] "file line is right: $t"
ok [string match "*do not edit below this line*" $t] "marker written"
set r [first [say info Alice $ALICE * "Alice female"]]
set t [filetext]
ok [string match {*sex="f"*} $t] "sex updated"
ok [string match {*pic="https://example.org/me.png"*} $t] "picture kept when only sex changes"
ok [string match "*female*" $r] "reply describes the profile"
say info Alice $ALICE * "Alice link=mailto-not https://new.example.org/x" ;# an invalid token must change nothing
ok [string match {*link="https://example.org"*} [filetext]] "invalid input changes nothing"
ok [string match "*don't understand*" [first [say info Alice $ALICE * "Alice blah"]]] "unknown word explained"

puts "3. claiming names"
reset
ok [string match "*only create a profile for the nick you are using*" [first [say info Bob $BOB * "Alice male"]]] "cannot create a profile for a nick you are not using"
say info Alice $ALICE * "Alice male"
ok [string match "*already taken*" [first [say info Alice $BOB * "Alice male"]]] "cannot take a name somebody has"
ok [string match "*don't have a profile called Alice*" [first [say merge Bob $BOB * "Alice"]]] "cannot merge into somebody else's profile"
say info Bob $BOB * "Bob male"
ok [string match "*already have a profile named Bob*" [first [say info Bob $BOB * "Zed male"]]] "one profile per account"
ok [string match "*already have a profile named Bob*" [first [say info Bob2 $BOB * "Bob2 male"]]] "still one profile per account"

puts "4. merging nicks"
reset
say info Alice $ALICE * "Alice male"
ok [string match "Done*" [first [say merge Alice_ $ALICE * "Alice"]]] "Alice_ merged into Alice"
ok [string match {*alias="Alice_"*} [filetext]] "alias written"
ok [string match "*already counted*" [first [say merge Alice_ $ALICE * "Alice"]]] "merging twice is harmless"
ok [string match "*already Alice*" [first [say merge Alice $ALICE * "Alice"]]] "merging the main nick into itself is refused"
say info Bob $BOB * "Bob male"
ok [string match "*already used by another profile*" [first [say merge Alice_ $BOB * "Bob"]]] "an alias held by someone else cannot be taken"
say merge Alice- $ALICE * "Alice"
ok [string match {*alias="Alice_ Alice-"*} [filetext]] "second alias appended"
ok [string match "Done*" [first [say unmerge Alice $ALICE * "Alice_"]]] "unmerge works"
ok [string match {*alias="Alice-"*} [filetext]] "alias removed"
ok [string match "*not one of your aliases*" [first [say unmerge Alice $ALICE * "Nobody"]]] "unmerge of a stranger refused"

puts "5. your hand-written lines are protected and preserved"
reset
set f [open $pisg::maincfg w]; puts $f "# main\n<user nick=\"Zed\" alias=\"Zeddy Z-\" sex=\"m\">"; close $f
set f [open $pisg::usersfile w]; puts $f "# my notes\n<user nick=\"Manny\" pic=\"a.png\">"; close $f
ok [string match "*already taken*" [first [say info Zed "~z@zed.users.undernet.org" * "Zed male"]]] "a nick from pisg.cfg cannot be claimed"
ok [string match "*already taken*" [first [say info Zeddy "~z@zeddy.users.undernet.org" * "Zeddy male"]]] "an alias from pisg.cfg cannot be claimed"
ok [string match "*already taken*" [first [say info Manny "~m@manny.users.undernet.org" * "Manny male"]]] "a hand-written line in users.cfg cannot be claimed"
say info Alice $ALICE * "Alice male"; say info Bob $BOB * "Bob male"
set t [filetext]
ok [string match "*# my notes*" $t] "your comment survives"
ok [string match {*<user nick="Manny" pic="a.png">*} $t] "your <user> line survives untouched"
ok [expr {[string first "# my notes" $t] < [string first "managed by" $t]}] "your part stays above the marker"
ok [expr {[string first {nick="Alice"} $t] < [string first {nick="Bob"} $t]}] "managed entries are sorted"
ok [string match "*set by hand*" [first [say show Alice $ALICE * "Zed"]]] "show says a hand-written profile exists"

puts "6. hostile and invalid input"
reset
foreach bad {
    "Alice male http://example.org/me.png"           "Alice male javascript:alert(1)"
    "Alice male https://localhost/me.png"             "Alice male https://127.0.0.1/me.png"
    "Alice male https://example.org/a\"b.png"         "Alice male https://example.org/me.png?x=<script>"
    "Alice male https://exa mple.org/me.png"          "Alice male https://example..org/me.png"
    "Se<b male"                                     "Alice sex=alien"
    "Alice male https://.org/x.png" } {
    set r [say info Alice $ALICE * $bad]
    ok [expr {![string match "Saved*" [first $r]]}] "refused: $bad"
}
ok [expr {![file exists $pisg::usersfile]}] "nothing written by any of them"
ok [pisg::valid_url "https://example.org/a/b?c=d"] "a normal https link is fine"
ok [expr {![pisg::valid_url "https://example.org/[string repeat a 300]"]}] "over-long links refused"
ok [pisg::valid_email "me@example.org"] "e-mail is a valid link"
ok [expr {![pisg::valid_email "me@example.org\"><b>"]}] "hostile e-mail refused"
set r [first [say info Alice $ALICE * "Alice me@example.org"]]
ok [string match "Saved*" $r] "an e-mail address works as the link"

puts "7. nicks with characters that are special in Tcl lists"
reset
set ODD "~o@odd.users.undernet.org"
ok [string match "Saved*" [first [say info {[x]{y}} $ODD * {[x]{y} male}]]] "profile for a nick with braces and brackets"
ok [string match "Done*" [first [say merge {a\b} $ODD * {[x]{y}}]]] "alias with a backslash"
ok [string match "Done*" [first [say merge {c|d^e} $ODD * {[x]{y}}]]] "alias with | and ^"
lassign [pisg::load] man ents
ok [expr {[llength $ents] == 1}] "one entry read back"
ok [expr {[dict get [lindex $ents 0] name] eq "{\[x\]{y}}" || [dict get [lindex $ents 0] name] eq {[x]{y}}}] "name read back exactly"
ok [expr {[dict get [lindex $ents 0] aliases] eq [list {a\b} {c|d^e}]}] "aliases read back exactly: [dict get [lindex $ents 0] aliases]"
set again [say show {a\b} $ODD * ""]
ok [expr {[string first {[x]{y}} [first $again]] >= 0 && [string first {a\b} [first $again]] >= 0}] "show works and prints the special characters literally: [first $again]"

puts "8. show, delete, delete-anybody"
reset
say info Alice $ALICE * "Alice male https://example.org/me.png"
ok [string match "*Alice: male*" [first [say show Bob $BOB * "Alice"]]] "anyone can look a profile up"
ok [string match "*No profile*" [first [say show Bob $BOB * "Nobody"]]] "unknown profile"
ok [string match "*no profile yet*" [first [say show Bob $BOB * ""]]] "no argument, no profile: says so"
ok [string match "*Alice: male*" [first [say show Alice $ALICE * ""]]] "no argument shows your own"
ok [string match "*You don't have a profile*" [first [say del Bob $BOB * ""]]] "delete without a profile"
ok [string match "*Only bot masters*" [first [say deluser Bob $BOB * "Alice"]]] "a normal user cannot delete somebody else's"
ok [string match "Deleted*" [first [say deluser Boss "~b@boss.users.undernet.org" boss "Alice"]]] "a bot master can"
ok [expr {![string match {*nick="Alice"*} [filetext]]}] "gone from the file"
say info Alice $ALICE * "Alice male"
ok [string match "Deleted*" [first [say del Alice $ALICE * ""]]] "you can delete your own"
ok [expr {![string match {*nick="Alice"*} [filetext]]}] "gone from the file"
set f [open $pisg::maincfg w]; puts $f "<user nick=\"Zed\">"; close $f
ok [string match "*written by hand*" [first [say deluser Boss "~b@boss.users.undernet.org" boss "Zed"]]] "a bot master cannot delete a hand-written entry"

puts "9. help"
reset
set r [say help Alice $ALICE * ""]
ok [string match "*pisginfo*pisgmerge*pisgshow*" [first $r]] "lists the commands"
ok [string match "*!pisghelp pisgshow*" [first $r]] "gives the !pisghelp <command> example"
foreach c {pisginfo pisgmerge pisgunmerge pisgshow pisgdel pisgdeluser pisgstats pisghelp} {
    ok [string match "*$c*" [first [say help Alice $ALICE * $c]]] "help for $c"
}
ok [string match "*pisgshow*" [first [say help Alice $ALICE * "!pisgshow"]]] "!pisgshow accepted"
ok [string match "*pisgshow*" [first [say help Alice $ALICE * "show"]]] "'show' short form accepted"
ok [string match "*don't know a command*" [first [say help Alice $ALICE * "nonsense"]]] "unknown command"

puts "10. rate limits"
reset
set pisg::minsecs 5
say info Alice $ALICE * "Alice male"
ok [string match "*Slow down*" [first [say info Alice $ALICE * "Alice female"]]] "two changes in a row are slowed"
ok [string match "*Alice*" [first [say show Alice $ALICE * ""]]] "reading is never slowed"
set pisg::minsecs 0; set pisg::maxperhour 3; array unset pisg::hist
for {set i 0} {$i < 3} {incr i} { say info Alice $ALICE * "Alice male" }
ok [string match "*Slow down*" [first [say info Alice $ALICE * "Alice female"]]] "too many changes in an hour are refused"
ok [string match "*Alice*" [first [say show Alice $ALICE * ""]]] "still can read"
set pisg::maxperhour 30

puts "11. replies stay short enough for IRC, and carry no control codes"
reset
set long "https://example.org/[string repeat p 250].png"
say info Alice $ALICE * "Alice male $long https://example.org/[string repeat q 250]"
foreach l [say show Alice $ALICE * ""] { ok [expr {[string length $l] <= 400}] "line is [string length $l] characters" }
ok [expr {[pisg::clean "a\x01b\x02c\r\nd"] eq "a b c  d"}] "control codes removed"

puts "12. bindings"
set types {}; foreach b $::binds { lappend types [lrange $b 0 2] }
foreach c {help info merge unmerge show del deluser} {
    ok [expr {[lsearch $types "pub - !pisg$c"] >= 0}] "channel command !pisg$c"
    ok [expr {[lsearch $types "msg - pisg$c"] >= 0}] "private message pisg$c"
}
ok [expr {[lsearch $types "pub - !pisgstats"] >= 0}] "!pisgstats is open to everyone"

file delete -force $tmp
puts "\n$passes passed, $fails failed"
exit [expr {$fails ? 1 : 0}]
