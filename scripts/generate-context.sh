#!/usr/bin/env bash
# ==============================================================================
# starlight-context-generator.sh
#
# Generates a consolidated markdown context file (starlight-app-context.md)
# tailored for AI context windows, reasoning, and automated code review.
#
# Key Features:
# 1. Strict maximum file size enforcement (configurable constant).
# 2. Strict whitelist of allowed file extensions.
# 3. Complete directory catalog of all application files (names, sizes, paths).
# 4. Primary focus files: Injected verbatim with language-specific syntax fences.
# 5. Secondary focus files: Injected as concise AI metadata (imports, method
#    signatures, declarations, and line stats) without full raw bodies.
# 6. Omitted files accounting: Accurately records files dropped due to size limits.
# 7. GitHub Actions staged logging using ::group:: and ::endgroup:: primitives.
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONFIGURATION CONSTANTS (Adjustable)
# ==============================================================================

# Maximum allowed file size for starlight-app-context.md in bytes.
# Default: 500 KB (512,000 bytes). Adjust this constant as needed.
readonly MAX_OUTPUT_SIZE_BYTES=$((500 * 1024))

# Final output markdown file name
readonly OUTPUT_FILE="starlight-app-context.md"

# Allowed file extensions for content inspection and concatenation
readonly ALLOWED_EXTENSIONS=(
  "kt"
  "java"
  "kts"
  "xml"
  "toml"
  "properties"
  "md"
  "json"
  "pro"
  "gradle"
  "yml"
  "yaml"
  "txt"
)

# PRIMARY FOCUS FILES:
# Core business logic, architecture, and manifests.
# Contents are included VERBATIM.
readonly PRIMARY_FILES=(
  "app/src/main/java/com/inscopelabs/abx/starlight/AutoService.kt"
  "app/src/main/java/com/inscopelabs/abx/starlight/RpcServer.kt"
  "app/src/main/java/com/inscopelabs/abx/starlight/MainActivity.kt"
  "app/src/main/AndroidManifest.xml"
  "app/src/main/res/xml/accessibility_service_config.xml"
  "app/build.gradle.kts"
  "gradle/libs.versions.toml"
  "README.md"
)

# SECONDARY FOCUS FILES:
# Supporting configurations, themes, build logic, and layout scaffolding.
# Only metadata, imports, method/class signatures, and structure are included.
readonly SECONDARY_FILES=(
  "build.gradle.kts"
  "settings.gradle.kts"
  "gradle.properties"
  "app/proguard-rules.pro"
  "app/src/main/res/layout/activity_main.xml"
  "app/src/main/res/values/strings.xml"
  "app/src/main/res/values/colors.xml"
  "app/src/main/res/values/themes.xml"
  "app/src/main/res/xml/backup_rules.xml"
  "app/src/main/res/xml/data_extraction_rules.xml"
  "gradle/wrapper/gradle-wrapper.properties"
  ".github/workflows/build-apk-debug.yml"
)

# Directories and patterns to ignore from directory scanning
readonly IGNORE_DIRS=(
  ".git"
  ".gradle"
  "build"
  "app/build"
  ".build-outputs"
  ".idea"
)

# ==============================================================================
# LOGGING AND FORMATTING HELPERS
# ==============================================================================

# Starts a GitHub Actions log group or falls back to terminal header
stage_start() {
  local stage_title="$1"
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::group::${stage_title}"
  else
    echo "======================================================================"
    echo ">>> ${stage_title}"
    echo "======================================================================"
  fi
}

# Closes a GitHub Actions log group
stage_end() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::endgroup::"
  fi
}

# Convert byte count to human-readable format (B, KB, MB)
format_human_size() {
  local bytes="$1"
  if [[ "$bytes" -ge 1048576 ]]; then
    printf "%.2f MB" "$(awk "BEGIN {print $bytes/1048576}")"
  elif [[ "$bytes" -ge 1024 ]]; then
    printf "%.2f KB" "$(awk "BEGIN {print $bytes/1024}")"
  else
    printf "%d B" "$bytes"
  fi
}

# Get file size in bytes
get_file_size() {
  local file_path="$1"
  if [[ -f "$file_path" ]]; then
    wc -c < "$file_path" | tr -d ' '
  else
    echo "0"
  fi
}

# Determine language identifier for Markdown code fences
get_syntax_highlight() {
  local filename="$1"
  local ext="${filename##*.}"
  case "$ext" in
    kt) echo "kotlin" ;;
    kts) echo "kotlin" ;;
    java) echo "java" ;;
    xml) echo "xml" ;;
    toml) echo "toml" ;;
    properties) echo "properties" ;;
    md) echo "markdown" ;;
    json) echo "json" ;;
    pro) echo "prolog" ;;
    yml|yaml) echo "yaml" ;;
    sh) echo "bash" ;;
    *) echo "" ;;
  esac
}

# Check if a file extension is in the allowed list
is_allowed_extension() {
  local file_path="$1"
  local ext="${file_path##*.}"
  for allowed in "${ALLOWED_EXTENSIONS[@]}"; do
    if [[ "$ext" == "$allowed" ]]; then
      return 0
    fi
  done
  return 1
}

# ==============================================================================
# SECONDARY FILE METADATA EXTRACTION
# ==============================================================================

extract_secondary_summary() {
  local file_path="$1"
  local ext="${file_path##*.}"

  echo "#### Key Signatures & Structural Metadata:"
  echo ""

  case "$ext" in
    kt|java)
      echo '```kotlin'
      # Extract package
      grep -E '^[[:space:]]*package[[:space:]]+' "$file_path" || true
      echo ""
      # Extract imports
      echo "// --- Imports ---"
      grep -E '^[[:space:]]*import[[:space:]]+' "$file_path" || true
      echo ""
      # Extract class/interface/object headers & functions
      echo "// --- Class, Interface & Method Signatures ---"
      grep -E '^[[:space:]]*(public[[:space:]]+|private[[:space:]]+|protected[[:space:]]+|internal[[:space:]]+|override[[:space:]]+|abstract[[:space:]]+|open[[:space:]]+)*(class|interface|object|enum class|data class|fun|val|var)[[:space:]]+' "$file_path" | sed -e 's/{[[:space:]]*$//' || true
      echo '```'
      ;;
    xml)
      echo '```xml'
      # Extract root tag and major component tags
      head -n 2 "$file_path"
      echo "<!-- Major Components & Attributes -->"
      grep -E '^[[:space:]]*<[A-Za-z0-9_.-]+([[:space:]]+[^>]*)?>?' "$file_path" | grep -v '^[[:space:]]*<!--' | head -n 35 || true
      echo '```'
      ;;
    gradle|kts)
      echo '```kotlin'
      echo "// --- Plugins & Dependencies Outline ---"
      grep -E '^[[:space:]]*(plugins|alias|implementation|compileOnly|runtimeOnly|testImplementation|android|signingConfigs|buildTypes)[[:space:]]*(\{|\\()' "$file_path" || true
      grep -E '^[[:space:]]*(namespace|applicationId|compileSdk|minSdk|targetSdk|versionCode|versionName|jvmTarget)' "$file_path" || true
      echo '```'
      ;;
    toml)
      echo '```toml'
      echo "# --- Versions & Library Keys ---"
      grep -E '^[[:space:]]*(\[[a-zA-Z0-9_-]+\]|[a-zA-Z0-9_-]+[[:space:]]*=)' "$file_path" | head -n 35 || true
      echo '```'
      ;;
    properties)
      echo '```properties'
      echo "# --- Configuration Properties ---"
      grep -E '^[[:space:]]*[a-zA-Z0-9_.-]+=' "$file_path" || true
      echo '```'
      ;;
    *)
      echo '```text'
      head -n 25 "$file_path"
      echo '```'
      ;;
  esac
}

# ==============================================================================
# EXECUTION PIPELINE
# ==============================================================================

# Working temp files
TMP_DIR="$(mktemp -d)"
TMP_PRIMARY="${TMP_DIR}/primary.md"
TMP_SECONDARY="${TMP_DIR}/secondary.md"
TMP_DIR_LIST="${TMP_DIR}/directory_listing.md"
TMP_FINAL="${TMP_DIR}/final_context.md"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Tracking omitted files
declare -a OMITTED_FILES_NAME=()
declare -a OMITTED_FILES_PATH=()
declare -a OMITTED_FILES_SIZE=()
declare -a OMITTED_FILES_REASON=()

# ------------------------------------------------------------------------------
# STAGE 1: INITIALIZATION & ENVIRONMENT AUDIT
# ------------------------------------------------------------------------------
stage_start "Stage 1: Initialization & Environment Audit"

echo "Repository Root: $(pwd)"
echo "Target Output File: ${OUTPUT_FILE}"
echo "Maximum Size Limit: $(format_human_size ${MAX_OUTPUT_SIZE_BYTES}) (${MAX_OUTPUT_SIZE_BYTES} bytes)"
echo "Allowed Extensions: ${ALLOWED_EXTENSIONS[*]}"
echo "Primary Focus Files (${#PRIMARY_FILES[@]} files configured)"
echo "Secondary Focus Files (${#SECONDARY_FILES[@]} files configured)"

stage_end

# ------------------------------------------------------------------------------
# STAGE 2: COMPLETE DIRECTORY CATALOGING
# ------------------------------------------------------------------------------
stage_start "Stage 2: Scanning Repository & Building Complete Directory Catalog"

echo "Scanning repository files..."

cat << 'EOF' > "$TMP_DIR_LIST"
## Complete Repository Directory Catalog

The table below provides a full inventory of all files present within the application repository, including file name, relative path, exact size in bytes, and human-readable size.

| File Name | Size (Bytes) | Human Size | Relative Path |
| :--- | :--- | :--- | :--- |
EOF

TOTAL_FILES=0
TOTAL_REPO_BYTES=0

# Find all regular files, excluding ignored directories
while IFS= read -r -d '' file_entry; do
  # Remove leading ./
  rel_path="${file_entry#./}"
  
  # Check against ignored directories
  skip=0
  for ign in "${IGNORE_DIRS[@]}"; do
    if [[ "$rel_path" == "$ign"* || "$rel_path" == *"/$ign/"* ]]; then
      skip=1
      break
    fi
  done
  if [[ $skip -eq 1 ]]; then
    continue
  fi

  file_name="$(basename "$rel_path")"
  file_bytes="$(get_file_size "$rel_path")"
  human_size="$(format_human_size "$file_bytes")"

  echo "| \`${file_name}\` | ${file_bytes} | ${human_size} | \`${rel_path}\` |" >> "$TMP_DIR_LIST"

  TOTAL_FILES=$((TOTAL_FILES + 1))
  TOTAL_REPO_BYTES=$((TOTAL_REPO_BYTES + file_bytes))
done < <(find . -type f -print0 | sort -z)

echo "Cataloged ${TOTAL_FILES} files with a total size of $(format_human_size ${TOTAL_REPO_BYTES}) (${TOTAL_REPO_BYTES} bytes)."

stage_end

# ------------------------------------------------------------------------------
# STAGE 3: PROCESS PRIMARY FOCUS FILES (VERBATIM)
# ------------------------------------------------------------------------------
stage_start "Stage 3: Processing Primary Focus Files (Verbatim Contents)"

cat << 'EOF' > "$TMP_PRIMARY"
## Primary Focus Files (Verbatim Code)

The following files represent the core business logic, accessibility automation service, remote RPC protocols, and build configuration of the application. Their contents are provided verbatim.

EOF

# Reserve budget for headers, directory catalog, secondary metadata, and summary
# We track size dynamically
RESERVED_FOOTER_BUDGET=5120 # 5KB buffer for summary table and footer

current_size=$(get_file_size "$TMP_DIR_LIST")

for file in "${PRIMARY_FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "[-] Primary file missing: ${file} (Skipping)"
    continue
  fi

  if ! is_allowed_extension "$file"; then
    echo "[-] Extension not allowed for ${file} (Skipping)"
    continue
  fi

  file_size=$(get_file_size "$file")
  syntax=$(get_syntax_highlight "$file")
  file_name=$(basename "$file")

  # Build temporary section
  tmp_section="${TMP_DIR}/section_primary.tmp"
  cat << EOF > "$tmp_section"
### File: \`${file}\`
- **Path**: \`${file}\`
- **File Name**: \`${file_name}\`
- **Size**: $(format_human_size "$file_size") (${file_size} bytes)
- **Mode**: Verbatim

\`\`\`${syntax}
EOF
  cat "$file" >> "$tmp_section"
  echo -e "\n\`\`\`\n" >> "$tmp_section"

  section_size=$(get_file_size "$tmp_section")

  # Check size limit
  if (( current_size + section_size + RESERVED_FOOTER_BUDGET > MAX_OUTPUT_SIZE_BYTES )); then
    echo "[!] SIZE LIMIT REACHED: Omitting primary file: ${file} ($(format_human_size "$file_size"))"
    OMITTED_FILES_NAME+=("$file_name")
    OMITTED_FILES_PATH+=("$file")
    OMITTED_FILES_SIZE+=("$file_size")
    OMITTED_FILES_REASON+=("Exceeded maximum size budget during primary concatenation")
  else
    echo "[+] Ingesting primary file verbatim: ${file} ($(format_human_size "$file_size"))"
    cat "$tmp_section" >> "$TMP_PRIMARY"
    current_size=$((current_size + section_size))
  fi
  rm -f "$tmp_section"
done

stage_end

# ------------------------------------------------------------------------------
# STAGE 4: PROCESS SECONDARY FOCUS FILES (STRUCTURE & SIGNATURES)
# ------------------------------------------------------------------------------
stage_start "Stage 4: Processing Secondary Focus Files (Signatures & Metadata)"

cat << 'EOF' > "$TMP_SECONDARY"
## Secondary Focus Files (Signatures & Structural Metadata)

The following secondary focus files provide structural configurations, resources, and scaffolding. Full verbatim bodies are omitted; only critical declarations, method signatures, imports, and metadata are extracted for AI reasoning.

EOF

for file in "${SECONDARY_FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "[-] Secondary file missing: ${file} (Skipping)"
    continue
  fi

  if ! is_allowed_extension "$file"; then
    echo "[-] Extension not allowed for ${file} (Skipping)"
    continue
  fi

  file_size=$(get_file_size "$file")
  file_name=$(basename "$file")
  line_count=$(wc -l < "$file" | tr -d ' ')
  word_count=$(wc -w < "$file" | tr -d ' ')

  tmp_section="${TMP_DIR}/section_secondary.tmp"
  cat << EOF > "$tmp_section"
### File: \`${file}\`
- **Path**: \`${file}\`
- **File Name**: \`${file_name}\`
- **Size**: $(format_human_size "$file_size") (${file_size} bytes)
- **Lines**: ${line_count} | **Words**: ${word_count}
- **Mode**: Metadata & Structural Extraction

EOF
  extract_secondary_summary "$file" >> "$tmp_section"
  echo "" >> "$tmp_section"

  section_size=$(get_file_size "$tmp_section")

  # Check size limit
  if (( current_size + section_size + RESERVED_FOOTER_BUDGET > MAX_OUTPUT_SIZE_BYTES )); then
    echo "[!] SIZE LIMIT REACHED: Omitting secondary file: ${file} ($(format_human_size "$file_size"))"
    OMITTED_FILES_NAME+=("$file_name")
    OMITTED_FILES_PATH+=("$file")
    OMITTED_FILES_SIZE+=("$file_size")
    OMITTED_FILES_REASON+=("Exceeded maximum size budget during secondary concatenation")
  else
    echo "[+] Ingesting secondary summary: ${file} ($(format_human_size "$file_size"))"
    cat "$tmp_section" >> "$TMP_SECONDARY"
    current_size=$((current_size + section_size))
  fi
  rm -f "$tmp_section"
done

stage_end

# ------------------------------------------------------------------------------
# STAGE 5: ASSEMBLE OUTPUT & ACCOUNT FOR OMITTED FILES
# ------------------------------------------------------------------------------
stage_start "Stage 5: Assembling Final Context Document & Verification"

GENERATED_TIMESTAMP="$(date -u +"%Y-%m-%d %H:%M:%S UTC")"

cat << EOF > "$TMP_FINAL"
# Starlight Application AI Context (\`starlight-app-context.md\`)

> **Generated**: ${GENERATED_TIMESTAMP}  
> **Repository Root**: \`com.inscopelabs.abx.starlight\`  
> **Max Size Cap**: $(format_human_size "$MAX_OUTPUT_SIZE_BYTES") (${MAX_OUTPUT_SIZE_BYTES} bytes)  
> **Allowed Extensions**: \`${ALLOWED_EXTENSIONS[*]}\`  

---

EOF

cat "$TMP_DIR_LIST" >> "$TMP_FINAL"
echo -e "\n---\n" >> "$TMP_FINAL"
cat "$TMP_PRIMARY" >> "$TMP_FINAL"
echo -e "\n---\n" >> "$TMP_FINAL"
cat "$TMP_SECONDARY" >> "$TMP_FINAL"
echo -e "\n---\n" >> "$TMP_FINAL"

# Omitted Files Summary
cat << EOF >> "$TMP_FINAL"
## Size Limit Enforcement & Omitted Files Accounting

- **Configured Maximum File Size**: $(format_human_size "$MAX_OUTPUT_SIZE_BYTES") (${MAX_OUTPUT_SIZE_BYTES} bytes)
- **Total Files Omitted Due to Size Budget**: ${#OMITTED_FILES_NAME[@]}

EOF

if [[ ${#OMITTED_FILES_NAME[@]} -eq 0 ]]; then
  cat << 'EOF' >> "$TMP_FINAL"
**Status**: All designated primary and secondary focus files were successfully accommodated within the configured size budget. No files were omitted.
EOF
else
  cat << 'EOF' >> "$TMP_FINAL"
| Omitted File Name | Size (Bytes) | Human Size | Relative Path | Reason |
| :--- | :--- | :--- | :--- | :--- |
EOF
  for i in "${!OMITTED_FILES_NAME[@]}"; do
    h_size=$(format_human_size "${OMITTED_FILES_SIZE[$i]}")
    echo "| \`${OMITTED_FILES_NAME[$i]}\` | ${OMITTED_FILES_SIZE[$i]} | ${h_size} | \`${OMITTED_FILES_PATH[$i]}\` | ${OMITTED_FILES_REASON[$i]} |" >> "$TMP_FINAL"
  done
fi

# Move temporary file to final output
mv "$TMP_FINAL" "$OUTPUT_FILE"

FINAL_OUTPUT_SIZE=$(get_file_size "$OUTPUT_FILE")
echo "Generated ${OUTPUT_FILE} successfully."
echo "Final Output Size: $(format_human_size "$FINAL_OUTPUT_SIZE") (${FINAL_OUTPUT_SIZE} bytes)"
echo "Files omitted due to size: ${#OMITTED_FILES_NAME[@]}"

if (( FINAL_OUTPUT_SIZE > MAX_OUTPUT_SIZE_BYTES )); then
  echo "::error::Output file size (${FINAL_OUTPUT_SIZE} bytes) exceeds MAX_OUTPUT_SIZE_BYTES (${MAX_OUTPUT_SIZE_BYTES} bytes)!"
  exit 1
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat << EOF >> "$GITHUB_STEP_SUMMARY"
### Starlight Context Generation Summary
- **Output File**: \`${OUTPUT_FILE}\`
- **Output Size**: $(format_human_size "$FINAL_OUTPUT_SIZE") (${FINAL_OUTPUT_SIZE} bytes / limit: $(format_human_size "$MAX_OUTPUT_SIZE_BYTES"))
- **Total Cataloged Files**: ${TOTAL_FILES}
- **Omitted Files Due to Size**: ${#OMITTED_FILES_NAME[@]}
EOF
fi

stage_end
echo "Process completed successfully."
