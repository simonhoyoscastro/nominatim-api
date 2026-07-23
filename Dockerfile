FROM mediagis/nominatim:5.3

# Antioquia-only (bbox-clipped from the full Colombia extract, since Geofabrik
# doesn't offer department-level extracts), reverse-lookup-only import: keeps
# the dataset light since we only need address/postcode data, not full
# search-index/POI data. Scoped down from full-country to fit the current
# Railway plan's 5GB volume cap — see README's "Changing region" section to
# restore full Colombia coverage once on a larger volume.
ENV PBF_URL=https://raw.githubusercontent.com/simonhoyoscastro/nominatim-api/main/data/antioquia-latest.osm.pbf
ENV IMPORT_STYLE=address
ENV REVERSE_ONLY=true
ENV FREEZE=true

COPY wrapper/main.py /app/wrapper/main.py
COPY docker/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 8000

CMD ["/app/entrypoint.sh"]
