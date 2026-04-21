#!/bin/bash

echo ""
echo "📝 [TEST 5/10] Validating YAML syntax..."
echo ""

YAML_PASS=0
YAML_FAIL=0
SKIPPED=0

for yaml_file in $(find . -name "*.yaml" -o -name "*.yml" 2>/dev/null | grep -v ".terraform" | grep -v "__pycache__" | sort); do
    # Skip Helm templates - they contain Go template syntax
    if [[ "$yaml_file" == *"/templates/"* ]] && [[ "$yaml_file" != *"values"* ]]; then
        echo "  ⏭️  $yaml_file (Helm template - validated by helm lint)"
        ((SKIPPED++))
        continue
    fi
    
    # Skip empty files
    if [ ! -s "$yaml_file" ]; then
        echo "  ⚠️  $yaml_file (empty file)"
        # Remove empty file if it's helm-deploy.yml
        if [[ "$yaml_file" == *"helm-deploy.yml"* ]]; then
            rm -f "$yaml_file"
            echo "     → Removed empty file"
        fi
        continue
    fi
    
    # Basic YAML validation using Python
    if python3 -c "
import yaml
import sys
try:
    with open('$yaml_file', 'r') as f:
        list(yaml.safe_load_all(f))
    sys.exit(0)
except Exception as e:
    sys.exit(1)
" 2>/dev/null; then
        ((YAML_PASS++))
    else
        echo "  ❌ $yaml_file - INVALID YAML"
        ((YAML_FAIL++))
    fi
done

echo ""
echo "  YAML files: $YAML_PASS valid, $SKIPPED skipped (Helm templates), $YAML_FAIL invalid"
