import csv
import os
import shutil
from pathlib import Path
from datetime import datetime

# Включение цветного вывода для Windows
if os.name == 'nt':
    os.system('color')

# Структура папок
BASE_DIR = Path(__file__).parent
DICT_DIR = BASE_DIR / "dict"
IN_DIR = BASE_DIR / "in"
REPORTS_DIR = BASE_DIR / "reports"
ARCH_DIR = BASE_DIR / "arch"

# Создаем папки
for dir_path in [DICT_DIR, IN_DIR, REPORTS_DIR, ARCH_DIR]:
    dir_path.mkdir(exist_ok=True)

def print_color(text, color='green'):
    colors = {
        'green': '\033[92m',
        'red': '\033[91m',
        'end': '\033[0m'
    }
    print(f"{colors.get(color, '')}{text}{colors['end']}")

try:
    # Загрузка справочников
    qris = []
    with open(DICT_DIR / "Сущности.csv", mode="r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter=";")
        for row in reader:
            if row.get("Тип") == "IT-система" and row.get("Тип ЦС") == "Прикладная":
                qris.append({
                    "РИС ИД": row["РИС ИД"],
                    "Общепринятое короткое название": row["Общепринятое короткое название"],
                    "Идентификационный код системы": row["Идентификационный код системы"]
                })

    with open(DICT_DIR / "Общебанк.csv", mode="r", encoding="utf-8") as f:
        obank = {row["рис ID"]: row for row in csv.DictReader(f, delimiter=";")}

    qris_map = {item["Идентификационный код системы"]: item for item in qris}

    processed_files = 0
    total_records = 0
    
    for input_file in IN_DIR.glob("Выгрузка РО *.csv"):
        try:
            # Извлекаем дату из имени файла
            date_part = input_file.stem.split()[-1]
            
            with open(input_file, mode="r", encoding="utf-8") as f:
                reader = csv.DictReader(f, delimiter=";")
                input_rows = list(reader)

            report_data = []
            for row in input_rows:
                ris_code = row.get("РИС код")
                if ris_code and ris_code in qris_map:
                    ris_id = qris_map[ris_code]["РИС ИД"]
                    if ris_id in obank:
                        report_data.append({
                            "рис ID": ris_id,
                            "рис код": ris_code,
                            "Название": obank[ris_id]["Название"],
                            "Команда": obank[ris_id]["Команда"],
                            "Всего": row.get("Кол-во всего", ""),
                            "Описано": row.get("Кол-во описанных", "")
                        })

            if not report_data:
                print_color(f"Файл {input_file.name} не содержит подходящих записей", "red")
                continue

            # Сортировка данных
            report_data_sorted = sorted(report_data, key=lambda x: (x["Команда"], x["рис ID"]))

            # Формируем имя отчета
            report_filename = f"Выгрузка РО СПВиРС {date_part}.csv"
            report_file = REPORTS_DIR / report_filename
            
            # Сохранение отчета
            with open(report_file, mode="w", encoding="utf-8", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=["рис ID", "рис код", "Название", "Команда", "Всего", "Описано"], delimiter=";")
                writer.writeheader()
                writer.writerows(report_data_sorted)

            # Перемещение исходного файла в архив
            arch_file = ARCH_DIR / input_file.name
            if arch_file.exists():
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                arch_file = ARCH_DIR / f"{input_file.stem}_{timestamp}{input_file.suffix}"
                
            shutil.move(str(input_file), str(arch_file))
            
            processed_files += 1
            total_records += len(report_data_sorted)
            print_color(f"Обработан: {input_file.name} -> {report_file.name} (записей: {len(report_data_sorted)})", "green")

        except Exception as e:
            print_color(f"Ошибка при обработке файла {input_file.name}: {str(e)}", "red")

    if processed_files > 0:
        print_color(f"\nИтоги обработки:", "green")
        print_color(f"• Успешно обработано файлов: {processed_files}", "green")
        print_color(f"• Всего записей в отчетах: {total_records}", "green")
        print_color(f"• Отчеты сохранены в: {REPORTS_DIR}", "green")
        print_color(f"• Архивные копии в: {ARCH_DIR}", "green")
    else:
        print_color("Нет файлов для обработки или ни один файл не содержал подходящих записей.", "red")

except Exception as e:
    print_color(f"Критическая ошибка: {str(e)}", "red")