#!/usr/bin/env bash
# 发布成功后保留指定数量的光影猫固件，同步删除旧发布附件与对应标签。
set -euo pipefail

keep=${1:-5}
current=${2:?需要本次成功发布的标签}
repo=${GITHUB_REPOSITORY:?缺少 GitHub 仓库名称}
pattern='^photonicat1-[0-9]{8}-[0-9]{6}-[0-9]+$'
[[ $keep =~ ^[1-9][0-9]*$ ]] || { echo '保留数量必须为正整数' >&2; exit 1; }
[[ $current =~ $pattern ]] || { echo '本次发布标签无效' >&2; exit 1; }
[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo '仓库名称无效' >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# 分页取全量发布；只处理本项目格式的已发布固件，包含正式版和预发行版。
gh api --paginate "repos/$repo/releases?per_page=100" --jq '.[]' > "$work/releases.ndjson"
jq -s --arg pattern "$pattern" '
  map(select(.draft == false and (.published_at|type) == "string" and
    (.tag_name|type) == "string" and (.tag_name|test($pattern))))
' "$work/releases.ndjson" > "$work/releases.json"
jq -e --arg current "$current" 'any(.[]; .tag_name == $current)' "$work/releases.json" >/dev/null || {
  echo '尚未找到本次成功发布的固件，停止清理旧发布' >&2
  exit 1
}
# 本次发布计入保留数；重复发布旧标签时也不删除刚上传的固件。
jq --arg current "$current" '
  sort_by([(.tag_name == $current), .published_at, .id]) | reverse
' "$work/releases.json" > "$work/ordered.json"
jq -r --argjson keep "$keep" '.[$keep:][].tag_name' "$work/ordered.json" > "$work/delete-tags"
jq -r --argjson keep "$keep" '.[:$keep][].tag_name' "$work/ordered.json" > "$work/keep-tags"

echo "保留以下固件发布（最多 $keep 个）："
cat "$work/keep-tags"
deleted=0
while IFS= read -r tag; do
  [ -n "$tag" ] || continue
  echo "删除旧发布、附件及标签：$tag"
  gh release delete "$tag" --repo "$repo" --yes --cleanup-tag
  deleted=$((deleted + 1))
done < "$work/delete-tags"
kept=$(wc -l < "$work/keep-tags")
echo "清理完成：保留 $kept 个固件发布，删除 $deleted 个旧发布及对应标签。"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo '### 固件发布保留结果'
    echo "- 设置保留：$keep 个（包含本次发布）"
    echo "- 实际保留：$kept 个"
    echo "- 删除旧发布、附件及对应标签：$deleted 个"
  } >> "$GITHUB_STEP_SUMMARY"
fi
