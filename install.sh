#!/usr/bin/env sh

odin build src -out:sync-conflicts -o:speed &&\
    cp sync-conflicts ~/.local/bin/ && \
    echo "Installed to ~/.local/bin/sync-conflicts"
