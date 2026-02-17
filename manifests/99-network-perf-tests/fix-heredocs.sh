#!/bin/bash

# Function to replace heredoc with temp file approach
fix_file() {
  local file=$1
  local marker=$2
  
  awk -v marker="$marker" '
    /<<- EOF_/{
      in_heredoc=1
      heredoc_marker=$NF
      gsub(/^.*<<- /, "", heredoc_marker)
      print "      cat > /tmp/sql_query.sql << '\''HEREDOC_" heredoc_marker "'\'' "
      next
    }
    in_heredoc && /^[[:space:]]*EOF_/{
      print "HEREDOC_" heredoc_marker
      print "      sqlite3 -separator \" \" \"$DB_FILE\" < /tmp/sql_query.sql"
      in_heredoc=0
      next
    }
    {print}
  ' "$file" > "$file.fixed"
  
  mv "$file.fixed" "$file"
}

fix_file "ib-tests-section.txt" "EOF_IB_DISPLAY"
fix_file "roce-tests-section.txt" "EOF_ROCE_DISPLAY"

echo "Fixed heredocs in both files"
