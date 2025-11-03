#!/bin/bash
# Script pour générer le CHANGELOG groupé par type puis par PR
# Usage: ./generate-changelog.sh <old_version> <new_version> <repo_url>

set -e

OLD_VERSION="$1"
NEW_VERSION="$2"
REPO_URL="$3"
DATE=$(date +%Y-%m-%d)

if [ -z "$OLD_VERSION" ] || [ -z "$NEW_VERSION" ] || [ -z "$REPO_URL" ]; then
  echo "Usage: $0 <old_version> <new_version> <repo_url>"
  exit 1
fi

echo "📝 Génération du CHANGELOG de ${OLD_VERSION} à v${NEW_VERSION}"

# Créer un fichier temporaire pour stocker les commits avec leur PR
TEMP_FILE="/tmp/commits_with_pr.json"
echo "[]" > "$TEMP_FILE"

# Récupérer tous les commits depuis la dernière version avec hash, message, type et PR
git log ${OLD_VERSION}..HEAD --pretty=format:"%H|%s" | while IFS='|' read -r hash message; do
  # Skip merge commits, revert commits, et automated commits
  if echo "$message" | grep -qE '^(Merge|Revert|\[Automated\]|chore\(release\))'; then
    continue
  fi

  # Vérifier si le commit respecte le format conventional commits
  if ! echo "$message" | grep -qE '^(feat|fix|hotfix|style|refactor|test|chore|docs)\([a-z0-9/_-]+\)(!)?:\s.+[^.]$'; then
    continue
  fi

  # Extraire le type du commit
  type=$(echo "$message" | sed -E 's/^([a-z]+)\(.*/\1/')

  # Trouver le numéro de PR associé au commit (via le message de merge squash)
  pr_number=$(git log --merges --ancestry-path ${hash}..HEAD --oneline 2>/dev/null | grep -oE '#[0-9]+' | head -1 | sed 's/#//')

  # Si pas de PR trouvée, chercher dans le message du commit
  if [ -z "$pr_number" ]; then
    pr_number=$(echo "$message" | grep -oE '\(#[0-9]+\)' | sed 's/[()#]//g')
  fi

  # Si toujours pas de PR, utiliser "direct"
  if [ -z "$pr_number" ]; then
    pr_number="direct"
  fi

  # Format: hash|message|type|pr_number
  echo "$hash|$message|$type|$pr_number"
done > /tmp/commits_list.txt

# Fonction pour afficher les commits d'un type et d'une PR avec liens
print_commits_for_type_and_pr() {
  local type="$1"
  local pr="$2"
  grep "|${type}|${pr}$" /tmp/commits_list.txt | while IFS='|' read -r hash message _ _; do
    # Raccourcir le hash à 7 caractères
    short_hash="${hash:0:7}"
    # Créer le lien vers le commit
    commit_link="[${short_hash}](${REPO_URL}/commit/${hash})"
    # Afficher le commit avec son lien
    echo "  * $message (${commit_link})"
  done
}

# Fonction pour afficher une section de type
print_section() {
  local type="$1"
  local emoji="$2"
  local section_name="$3"

  # Vérifier s'il y a des commits de ce type
  if ! grep -q "|${type}|" /tmp/commits_list.txt 2>/dev/null; then
    return
  fi

  echo ""
  echo "### ${emoji} ${section_name}"
  echo ""

  # Récupérer toutes les PRs uniques pour ce type
  grep "|${type}|" /tmp/commits_list.txt | cut -d'|' -f4 | sort -u | while read -r pr; do
    if [ "$pr" = "direct" ]; then
      # Commits directs sans PR
      print_commits_for_type_and_pr "$type" "$pr"
    else
      # Commits d'une PR avec lien vers la PR
      pr_link="[#${pr}](${REPO_URL}/pull/${pr})"
      echo "#### PR ${pr_link}"
      echo ""
      print_commits_for_type_and_pr "$type" "$pr"
      echo ""
    fi
  done
}

# Générer la nouvelle section du CHANGELOG
{
  echo "## [${NEW_VERSION}](${REPO_URL}/compare/${OLD_VERSION}...v${NEW_VERSION}) (${DATE})"

  # Sections dans l'ordre
  print_section "feat" "🚀" "Features"
  print_section "fix" "🐛" "Fixes"
  print_section "hotfix" "🐛" "Hotfixes"
  print_section "chore" "🧰" "Maintenance"
  print_section "docs" "📝" "Documentation"
  print_section "style" "🎨" "Style"
  print_section "refactor" "♻️" "Refactor"
  print_section "test" "🧪" "Tests"

  echo ""
} > /tmp/new_changelog_section.md

# Insérer la nouvelle section dans le CHANGELOG
if [ ! -f CHANGELOG.md ]; then
  echo "# CHANGELOG" > CHANGELOG.md
  echo "" >> CHANGELOG.md
fi

# Créer le nouveau CHANGELOG
if grep -q "^# CHANGELOG" CHANGELOG.md; then
  # Garder l'en-tête
  head -n 2 CHANGELOG.md > /tmp/changelog_new.md
  # Ajouter la nouvelle section
  cat /tmp/new_changelog_section.md >> /tmp/changelog_new.md
  # Ajouter les anciennes versions
  tail -n +3 CHANGELOG.md >> /tmp/changelog_new.md
  mv /tmp/changelog_new.md CHANGELOG.md
else
  cat /tmp/new_changelog_section.md CHANGELOG.md > /tmp/changelog_new.md
  mv /tmp/changelog_new.md CHANGELOG.md
fi

echo "✅ CHANGELOG généré avec succès"
cat /tmp/new_changelog_section.md
