#!/usr/bin/env bash
# ====================================================================
# Azkia Greeter Standalone Preview
# Jalankan skrip ini untuk melihat tampilan greeter secara langsung
# ====================================================================

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Memulai preview Azkia Greeter..."
echo "==> Tekan Ctrl+C di terminal ini atau tutup jendela untuk keluar."

qs -p "$DIR"
