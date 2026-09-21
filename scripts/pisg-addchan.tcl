# Original Author: paultwang - 2010-03-17
# fixed and tweaked: Seb 2017-10-25

# This is where pisg.cfg is stored
set pp_confname "/home/jedi/pisg/pisg-0.73/pisg.cfg"

# This is where your IRC logs are stored
set pp_baselogdir "/home/jedi/eggdrop/logs"

# This is the file extension of your logs
set pp_logfilesuffix ".%Y%m%d"

# This is where your output should be
set pp_baseoutputdir "/var/www/html/chanstats"

# This is the file extension of your output
set pp_outputsuffix ".html"

# Set IRC network name
set pp_networkname "Undernet"

# Set log file format
set pp_format "eggdrop"

# NOTE: When you add channel, it will make eggdrop start logging that channel


bind pub m|m !pisgadd pub_pisgadd
bind pub m|m !pisgdel pub_pisgdel
bind pub m|m !pisgreaddall pub_pisgreaddall

#STOP EDITING HERE
#STOP EDITING HERE

bind join - * join_autoaddbotselfjoin
proc pub_pisgadd {n u h c a} {
 if {[string length $a] == 0} {
  set chan $c
 } else {
  set chan [lindex [split $a] 0]
 }
 pp_addchan $chan
 puthelp "privmsg $c :Added $chan"
}

proc pub_pisgdel {n u h c a} {
 if {[string length $a] == 0} {
  set chan $c
 } else {
  set chan [lindex [split $a] 0]
 }
 pp_delchan $chan
 puthelp "privmsg $c :Deleted $chan"
}

proc pub_pisgreaddall {n u h c a} {
 pp_readdallchans
 puthelp "privmsg $c :Re-added all channels"

}


proc pp_toASCII {char} {
 return [scan $char %c]
}

proc pp_toASCIIHEX {string} {
 set hexvalue [list]
 foreach char [split $string ""] {
  lappend hexvalue [format %x [scan $char %c]]
 }
 return $hexvalue
}

proc pp_sanitizechanname {chan} {
 # This makes it suitable for filename
 set chan [string tolower [string range $chan 1 end]]
 set newchan [list]
 foreach char [split $chan ""] {
  set ascii [pp_toASCII $char]
  if {$ascii >= 48 && $ascii <= 57} {lappend newchan $char; continue}
  if {$ascii >= 65 && $ascii <= 90} {lappend newchan $char; continue}
  if {$ascii >= 97 && $ascii <= 122} {lappend newchan $char; continue}
  lappend newchan "%[join [pp_toASCIIHEX $char]]"  
 }
 set newchan [join $newchan ""]
 return $newchan
}


proc pp_addlog {chan} {
 global pp_baselogdir pp_logfilesuffix
 set logname [pp_sanitizechanname $chan]
 logfile "pjk" "$chan" "${pp_baselogdir}/${logname}${pp_logfilesuffix}"
}

proc pp_addlogfiles {} {
 foreach chan [channels] {
  pp_addlog $chan
 }
}

proc join_autoaddbotselfjoin {n u h chan} {
 if {[isbotnick $n]} {
  pp_addlog $chan
 }
}

proc pp_loadconf {} {
 global pp_confname
 set conflines [list]
 set fh [open $pp_confname "r"]
 for {set i 0} {![eof $fh]} {incr i} {
  lappend conflines [gets $fh]
 }
 close $fh
 return $conflines
}

proc pp_overwriteconf {conflines} {
 global pp_confname {temp-path}
 set fh [open "${pp_confname}.new" "w"]
 set lmax [llength $conflines]
 for {set i 0} {$i < $lmax} {incr i} {
  puts $fh [lindex $conflines $i]
 }
 close $fh
 file copy -force -- "${pp_confname}.new" $pp_confname
 file delete -- "${pp_confname}.new"
 return
}


proc pp_appendconf {addnewlines} {
 global pp_confname
 set fh [open $pp_confname "a"]
 set lmax [llength $addnewlines]
 for {set i 0} {$i < $lmax} {incr i} {
  puts $fh [lindex $addnewlines $i]
 }
 close $fh
 return
}

proc pp_findchaninconf {conflines} {
 set lmax [llength $conflines]
 set chanlines [list]
 set single [list]
 set begun 0
 for {set i 0} {$i < $lmax} {incr i} {
  set line [string trim [lindex $conflines $i]]
  if {!$begun && [string match "<channel=*>" $line]} {
   set channame [string tolower [join [lrange [split $line "\""] 1 end-1] "\""]]
   if {[string length $channame] == 0} {
    set channame "malform"
   }
   set single [list $channame]
   lappend single $i
   set begun 1
  } elseif {$begun && [string match "</channel>" $line]} {
   lappend single $i
   set begun 0
   lappend chanlines $single
  }
 }
 return $chanlines
}


proc pp_addchan {chan} {
 global pp_baselogdir pp_logfilesuffix pp_baseoutputdir pp_outputsuffix pp_networkname pp_format
 if {![string equal [string index $chan 0] "#"]} {
  putlog "autoadd err: Chan must begin with # sign"
  return
 }
 pp_addlog $chan

 set conflines [pp_loadconf]
 set chanlines [pp_findchaninconf $conflines]
 set lmax [llength $chanlines]
 for {set i 0} {$i < $lmax} {incr i} {
  if {[string equal -nocase $chan [lindex [lindex $chanlines $i] 0]]} {
   # Channel already exists. Ignore command.
   return
  }
 }
 set addnewlines [list]
 #puthelp "privmsg #ChanStats :debug 1"
 lappend addnewlines "<channel=\"${chan}\">"
 #lappend addnewlines "  Logfile=\"${pp_baselogdir}/${chan}${pp_logfilesuffix}\""
 lappend addnewlines "  LogDir=\"${pp_baselogdir}/\""
 lappend addnewlines "  LogPrefix=\"[pp_sanitizechanname ${chan}].\""
 lappend addnewlines "  Format=\"${pp_format}\""
 lappend addnewlines "  Network=\"${pp_networkname}\""
 lappend addnewlines "  OutputFile=\"${pp_baseoutputdir}/[pp_sanitizechanname ${chan}]${pp_outputsuffix}\""
 lappend addnewlines "</channel>"
 #puthelp "privmsg #ChanStats :debug 1.5"
 pp_appendconf $addnewlines
 #puthelp "privmsg #ChanStats :debug 2"
}

proc pp_delchan {chan} {
 global pp_logfilesuffix
 set conflines [pp_loadconf]
 set chanlines [pp_findchaninconf $conflines]
 set linestodelete [list]
 set lmax [llength $chanlines]


 for {set i 0} {$i < $lmax} {incr i} {
  if {[string equal -nocase $chan [lindex [lindex $chanlines $i] 0]]} {
   set linepair [lrange [lindex $chanlines $i] 1 2]
   lappend linestodelete $linepair
  }
 }
 set linestodelete [lsort -integer -index 0 -decreasing $linestodelete]
 set lmax [llength $linestodelete]
 for {set i 0} {$i < $lmax} {incr i} {
  set d [lindex $linestodelete $i]
  set conflines [lreplace $conflines [lindex $d 0] [lindex $d 1]]
 }
 pp_overwriteconf $conflines
}

proc pp_readdallchans {} {
 global pp_logfilesuffix
 set conflines [pp_loadconf]
 set chanlines [pp_findchaninconf $conflines]
 set linestodelete [list]
 set lmax [llength $chanlines]


 for {set i 0} {$i < $lmax} {incr i} {
  set linepair [lrange [lindex $chanlines $i] 1 2]
  lappend linestodelete $linepair
 }
 set linestodelete [lsort -integer -index 0 -decreasing $linestodelete]
 set lmax [llength $linestodelete]
 for {set i 0} {$i < $lmax} {incr i} {
  set d [lindex $linestodelete $i]
  set conflines [lreplace $conflines [lindex $d 0] [lindex $d 1]]
 }
 pp_overwriteconf $conflines
 foreach chan [channels] {
  pp_addchan $chan
 }
}

pp_addlogfiles
