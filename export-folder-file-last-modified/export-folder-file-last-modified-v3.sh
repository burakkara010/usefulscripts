#!/bin/bash

echo "Starting: Please Be Patient, this can take some time for huge folder structures"

# Output Excel-bestand
output_excel=~/Downloads/export-folder-file-last-modified.xlsx

# Vereist: Python met xlsxwriter en tqdm
if ! python3 -c "import xlsxwriter" &>/dev/null; then
    echo "Python 'xlsxwriter' module niet gevonden. Installeer het met: pip3 install xlsxwriter"
    exit 1
fi

if ! python3 -c "import tqdm" &>/dev/null; then
    echo "Python 'tqdm' module niet gevonden. Installeer het met: pip3 install tqdm"
    exit 1
fi

# Maak een Python-script dat Excel genereert
cat <<'EOF' > /tmp/export-folder-file-last-modified.py
import os
import xlsxwriter
import subprocess
from tqdm import tqdm  # Voor de voortgangsbalk

# Outputbestand
output_file = os.path.expanduser("~/Downloads/export-folder-file-last-modified.xlsx")

# Maak een Excel workbook
workbook = xlsxwriter.Workbook(output_file)

# Maak een algemene sheet voor alle folders en bestanden
worksheet_all = workbook.add_worksheet("All Folders & Files")
worksheet_all.write(0, 0, "Folder")
worksheet_all.write(0, 1, "Filename")
worksheet_all.write(0, 2, "Last Modified Date")

# Haal folders op in de huidige directory
folders = [d for d in os.listdir() if os.path.isdir(d)]

# Voeg bestanden van alle folders toe aan de "All Folders & Files" sheet
row_all = 1
for folder in tqdm(folders, desc="Processing folders", unit="folder"):
    # Haal bestanden gesorteerd op 'last modified date'
    result = subprocess.run(f"ls -lt '{folder}'", shell=True, capture_output=True, text=True)
    files = result.stdout.strip().split("\n")[1:]  # Eerste regel (total) overslaan
    
    for file_line in files:
        parts = file_line.split()
        if len(parts) >= 9:
            last_modified = f"{parts[5]} {parts[6]} {parts[7]}"  # Datum
            filename = " ".join(parts[8:])  # Bestandnaam
            worksheet_all.write(row_all, 0, folder)
            worksheet_all.write(row_all, 1, filename)
            worksheet_all.write(row_all, 2, last_modified)
            row_all += 1

# Maak een voortgangsbalk voor de folders
for folder in tqdm(folders, desc="Processing individual folders", unit="folder"):
    worksheet = workbook.add_worksheet(folder[:31])  # Max 31 tekens voor sheetnamen
    worksheet.write(0, 0, "Filename")
    worksheet.write(0, 1, "Last Modified Date")

    # Haal bestanden gesorteerd op 'last modified date'
    result = subprocess.run(f"ls -lt '{folder}'", shell=True, capture_output=True, text=True)
    files = result.stdout.strip().split("\n")[1:]  # Eerste regel (total) overslaan
    
    # Maak een voortgangsbalk voor de bestanden in elke folder
    for row, file_line in enumerate(tqdm(files, desc=f"Processing files in {folder}", unit="file", leave=False)):
        parts = file_line.split()
        if len(parts) >= 9:
            last_modified = f"{parts[5]} {parts[6]} {parts[7]}"  # Datum
            filename = " ".join(parts[8:])  # Bestandnaam
            worksheet.write(row + 1, 0, filename)
            worksheet.write(row + 1, 1, last_modified)

# Sla het Excel-bestand op
workbook.close()
print(f"Excel-bestand aangemaakt: {output_file}")
EOF

# Voer het Python-script uit
python3 /tmp/export-folder-file-last-modified.py
