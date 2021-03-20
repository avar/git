#!/bin/sh
#
# See ../t4018-diff-funcname.sh's test_diff_funcname()
#

test_diff_funcname 'ada: "procedure" over "with"' \
	8<<\EOF_HUNK 9<<\EOF_TEST
procedure Bottles is
EOF_HUNK
with Ada.Text_Io; use Ada.Text_Io;
 procedure Bottles is
 begin
    for X in reverse 1..99 loop
       Put_Line(Integer'Image(X) & " bottles of beer on the wall");
       Put_Line(Integer'Image(X) & " bottles of beer"); -- ChangeMe
       Put_Line("Take one down, pass it around");
       Put_Line(Integer'Image(X - 1) & " bottles of beer on the wall");
       New_Line;
    end loop;
 end Bottles;
EOF_TEST

test_diff_funcname 'ada: "task" over "procedure"' \
	8<<\EOF_HUNK 9<<\EOF_TEST
task body Check_CPU is
EOF_HUNK
procedure Housekeeping is
  task Check_CPU;
  task Backup_Disk;

  task body Check_CPU is
    -- Comment for spacing with
    -- the above "task" for -U1
    ChangeMe
  end Check_CPU;
end Housekeeping;
EOF_TEST
