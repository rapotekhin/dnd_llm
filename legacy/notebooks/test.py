import os

ld = os.listdir("legacy/game/dnd_5e_data/api/2014")

list_of_dirs = []
for file in ld:
    if os.path.isdir(f"legacy/game/dnd_5e_data/api/2014/{file}"):
        list_of_dirs.append(file)

print(list_of_dirs)