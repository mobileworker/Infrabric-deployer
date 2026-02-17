#!/usr/bin/env python3
"""
Build network performance test ConfigMaps from source sections.
Handles heredocs and SQL properly using Python.
"""

import re
import sys

def remove_heredoc_block(content, start_pattern, end_marker):
    """Remove a heredoc block and replace with a comment."""
    lines = content.split('\n')
    result = []
    in_heredoc = False
    heredoc_indent = 0
    
    for line in lines:
        if re.search(start_pattern, line):
            # Found start of heredoc
            in_heredoc = True
            heredoc_indent = len(line) - len(line.lstrip())
            result.append(' ' * heredoc_indent + '# SQL results stored in database')
            continue
        
        if in_heredoc:
            # Check if this is the end marker
            if line.strip() == end_marker:
                in_heredoc = False
            continue
        
        result.append(line)
    
    return '\n'.join(result)

def adjust_indentation(content, from_indent, to_indent):
    """Adjust indentation from one level to another."""
    lines = content.split('\n')
    result = []
    
    for line in lines:
        if line.strip():  # Non-empty line
            # Remove old indentation
            if line.startswith(' ' * from_indent):
                line = line[from_indent:]
            # Add new indentation
            line = ' ' * to_indent + line
        result.append(line)
    
    return '\n'.join(result)

def create_ib_configmap(source_file):
    """Create IB tests ConfigMap."""
    with open(source_file, 'r') as f:
        content = f.read()
    
    # Remove the SQL heredoc display
    content = remove_heredoc_block(content, r'sqlite3.*EOF_IB_DISPLAY', 'EOF_IB_DISPLAY')
    
    # Adjust indentation from 14 spaces (in original) to 4 spaces (in ConfigMap)
    content = adjust_indentation(content, 14, 4)
    
    # Build ConfigMap
    configmap = f"""---
apiVersion: v1
kind: ConfigMap
metadata:
  name: network-perf-ib-tests
  namespace: default
data:
  ib-tests.sh: |
    #!/bin/bash
    
    run_ib_tests() {{
      SOURCE_POD=$1
      TARGET_POD=$2
      SOURCE_NODE=$3
      TARGET_NODE=$4
      SOURCE_GPUS=$5
      TARGET_GPUS=$6
      
{content}
    }}
"""
    
    return configmap

def create_roce_configmap(source_file):
    """Create RoCE tests ConfigMap."""
    with open(source_file, 'r') as f:
        content = f.read()
    
    # Remove the SQL heredoc display
    content = remove_heredoc_block(content, r'sqlite3.*EOF_ROCE_DISPLAY', 'EOF_ROCE_DISPLAY')
    
    # Adjust indentation
    content = adjust_indentation(content, 14, 4)
    
    # Build ConfigMap
    configmap = f"""---
apiVersion: v1
kind: ConfigMap
metadata:
  name: network-perf-roce-tests
  namespace: default
data:
  roce-tests.sh: |
    #!/bin/bash
    
    run_roce_tests() {{
      SOURCE_POD=$1
      TARGET_POD=$2
      SOURCE_NODE=$3
      TARGET_NODE=$4
      SOURCE_GPUS=$5
      TARGET_GPUS=$6
      
{content}
    }}
"""
    
    return configmap

if __name__ == '__main__':
    base_path = '/Users/bbenshab/Infrabric-deployer/manifests/99-network-perf-tests'
    
    # Create IB ConfigMap
    ib_cm = create_ib_configmap(f'{base_path}/ib-tests-section.txt.bak')
    with open(f'{base_path}/ib-tests-configmap.yaml', 'w') as f:
        f.write(ib_cm)
    print("✓ Created ib-tests-configmap.yaml")
    
    # Create RoCE ConfigMap
    roce_cm = create_roce_configmap(f'{base_path}/roce-tests-section.txt.bak')
    with open(f'{base_path}/roce-tests-configmap.yaml', 'w') as f:
        f.write(roce_cm)
    print("✓ Created roce-tests-configmap.yaml")
