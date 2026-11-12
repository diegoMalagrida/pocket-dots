import re, glob, collections
dic = open("translations-it.js", encoding="utf-8").read()
have = set(re.findall(r'^\s*"((?:[^"\\]|\\.)*)"\s*:', dic, re.M))
miss = collections.defaultdict(set)
for f in sorted(glob.glob("*.qml")):
    src = open(f, encoding="utf-8").read()
    for s in re.findall(r'I18n\.tr\(\s*"((?:[^"\\]|\\.)*)"', src):
        if s not in have:
            miss[f].add(s)
for f, ss in miss.items():
    print(f"\n== {f} ({len(ss)})")
    for s in sorted(ss):
        print("  ", s)