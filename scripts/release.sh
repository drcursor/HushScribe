scripts/build_swift_app.sh;scripts/make_dmg.sh
echo 'gh release create v2.3.0 \
    dist/HushScribe.dmg \
    --title "HushScribe v2.3.0" \
    --notes "Release v2.3.0"'
