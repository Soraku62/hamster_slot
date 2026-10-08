#!/bin/sh
# Builds the web app and publishes it to the gh-pages branch
# (GitHub Pages: Settings > Pages > "Deploy from a branch" > gh-pages / root).
set -e
cd "$(dirname "$0")/.."
REPO=hamster_slot
REMOTE=$(git remote get-url origin)

# Pages serves the site under /<repo>/, so asset URLs need that prefix.
flutter build web --release --base-href "/$REPO/"

# Turn build/web into a throwaway git repo holding only the built files,
# then overwrite the gh-pages branch with it.
cd build/web
touch .nojekyll # tell Pages to serve files as-is (no Jekyll processing)
rm -rf .git
git init -q -b gh-pages
git add -A
git commit -q -m "Deploy $(date '+%Y-%m-%d %H:%M')"
git push -f "$REMOTE" gh-pages
rm -rf .git
echo "Deployed: https://$(echo "$REMOTE" | sed -E 's#https://github.com/([^/]+)/.*#\1#').github.io/$REPO/"
