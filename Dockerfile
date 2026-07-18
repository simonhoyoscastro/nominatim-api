FROM mediagis/nominatim:5.3

# Colombia-only, reverse-lookup-only import: keeps the dataset light since we
# only need address/postcode data, not full search-index/POI data.
ENV PBF_URL=https://download.geofabrik.de/south-america/colombia-latest.osm.pbf
ENV IMPORT_STYLE=address
ENV REVERSE_ONLY=true
ENV FREEZE=true

COPY wrapper/main.py /app/wrapper/main.py
COPY docker/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 8080

CMD ["/app/entrypoint.sh"]
