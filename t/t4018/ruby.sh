#!/bin/sh
#
# See ../t4018-diff-funcname.sh's test_diff_funcname()
#

test_diff_funcname 'ruby: "def" over "class/module"' \
	8<<\EOF_HUNK 9<<\EOF_TEST
def process(parent)
EOF_HUNK
require 'asciidoctor'

module Git
  module Documentation
    class SomeClass
      use_some

      def process(parent)
        puts("hello")
	puts(ChangeMe)
      end
    end
  end
end
EOF_TEST

test_diff_funcname 'ruby: "class" over "class/module"' \
	8<<\EOF_HUNK 9<<\EOF_TEST
class Two
EOF_HUNK
module Git
  module Documentation
    class One
    end

    class Two
      # Spacing for -U1
      ChangeMe
    end
  end
end
EOF_TEST

test_diff_funcname 'ruby: picks first "class/module/def" before changed context' \
	'-U1' \
	8<<\EOF_HUNK 9<<\EOF_TEST
class One
EOF_HUNK
module Git
  module Documentation
    class One
    end

    class Two
      ChangeMe
    end
  end
end
EOF_TEST
