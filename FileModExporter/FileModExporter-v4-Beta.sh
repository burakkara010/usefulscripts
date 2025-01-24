#!/bin/bash
echo -e "\033[1;32m"
echo "script: export-folder-file-last-modified-v3.sh"
echo -e "\033[0m"
echo -e "\033[1;33m"
echo "This script will create an Excel file with the last modified date of all files in the current directory, including nested folders."
echo -e "\033[0m"

# Vraag of individuele mappen sheets moeten worden aangemaakt
read -p "The first sheet of the Excel file will contain all folders and files, but you also can split the folders into separate sheets.
Do you want to create individual sheets per folder? (y/n): " create_individual_sheets
echo ""

echo "Starting: Please Be Patient, this can take some time for huge folder structures"

# Genereer een timestamp in het formaat: uur-minuut-dag-maand-jaar
timestamp=$(date +"%d%m-%Y-%H%M")

# Output Excel-bestand met timestamp
output_excel="$HOME/Downloads/export-folder-file-last-modified-${timestamp}.xlsx"

# Vereist: Python met xlsxwriter en tqdm
if ! python3 -c "import xlsxwriter" &>/dev/null; then
    echo "Python 'xlsxwriter' module not found. Install with: pip3 install xlsxwriter"
    exit 1
fi

if ! python3 -c "import tqdm" &>/dev/null; then
    echo "Python 'tqdm' module not found. Install with: pip3 install tqdm"
    exit 1
fi

# Maak een Python-script dat Excel genereert
cat <<EOF > /tmp/export-folder-file-last-modified.py
import os
import time
import xlsxwriter
from tqdm import tqdm  # for the progress bar

# Output file
output_file = os.path.expanduser("${output_excel}")

# Create an Excel workbook
workbook = xlsxwriter.Workbook(output_file)

# Create a general sheet for all folders and files
worksheet_all = workbook.add_worksheet("All Folders & Files")
worksheet_all.write(0, 0, "Folder")
worksheet_all.write(0, 1, "Filename")
worksheet_all.write(0, 2, "Last Modified Date")

# Add files from all folders, including nested folders, to the "All Folders & Files" sheet
row_all = 1
for root, dirs, files in tqdm(os.walk("."), desc="Processing folders", unit="folder"):
    folder = os.path.relpath(root, start=".")  # Relatief pad naar huidige folder
    for file in files:
        filepath = os.path.join(root, file)
        last_modified = os.path.getmtime(filepath)
        last_modified_date = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(last_modified))
        worksheet_all.write(row_all, 0, folder)
        worksheet_all.write(row_all, 1, file)
        worksheet_all.write(row_all, 2, last_modified_date)
        row_all += 1

# Ask if individual folder sheets should be created
create_individual_sheets = os.environ.get("CREATE_INDIVIDUAL_SHEETS", "n").lower() in ["y", "yes"]

if create_individual_sheets:
    # Make individual sheets for each folder
    for root, dirs, files in tqdm(os.walk("."), desc="Processing individual folders", unit="folder"):
        folder = os.path.relpath(root, start=".")
        if not files:  # Sla over als er geen bestanden in de map zijn
            continue
        worksheet = workbook.add_worksheet(folder[:31])  # Max 31 tekens voor sheet-namen
        worksheet.write(0, 0, "Filename")
        worksheet.write(0, 1, "Last Modified Date")

        for row, file in enumerate(files, start=1):
            filepath = os.path.join(root, file)
            last_modified = os.path.getmtime(filepath)
            last_modified_date = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(last_modified))
            worksheet.write(row, 0, file)
            worksheet.write(row, 1, last_modified_date)

# Save the Excel file
workbook.close()
print(f"Excel-File Created: {output_file}")
EOF

# Choice to create individual sheets
if [[ "$create_individual_sheets" =~ ^[yY](es)?$ ]]; then
    export CREATE_INDIVIDUAL_SHEETS="y"
else
    export CREATE_INDIVIDUAL_SHEETS="n"
fi

# Run the Python script
python3 /tmp/export-folder-file-last-modified.py
