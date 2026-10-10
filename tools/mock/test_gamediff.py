# python3 tools/mock/test_gamediff.py : verifie tools/gamediff.py sur deux inventaires d'exemple
import os, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
out = subprocess.run([sys.executable, os.path.join(root, "tools", "gamediff.py"), os.path.join(here, "fixtures", "scan_old.txt"), os.path.join(here, "fixtures", "scan_new.txt")],
                     capture_output=True, text=True, check=True).stdout
checks = {
    "removed remote listed": "- [REMOTE] RS/Remotes/Game/Teleporting" in out,
    "moved remote detected": "RS/Remotes/Game/BasketDrop  ->  RS/Remotes/Basket/BasketDrop" in out,
    "added remote listed": "+ [REMOTE] RS/Remotes/Game/NewThing" in out,
    "button text change": "texte 'DROP' -> 'DROP EGG'" in out,
    "prompt hold change": "hold=0.2' -> 'Pick Up / Dino / hold=0.5" in out,
    "impact limited to the game's scripts": "yslempet_EggTP.lua" in out and "SourcesHub.lua" not in out.split("IMPACT")[1],
    "impact names the moved remote": "! DEPLACE [REMOTE] BasketDrop" in out,
}
bad = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    print(("ok   " if v else "FAIL ") + k)
sys.exit(1 if bad else 0)
