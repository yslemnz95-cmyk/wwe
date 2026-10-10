#!/usr/bin/env python3
"""Remplit une base de DEMO avec de fausses executions (pour voir le dashboard). Usage : python3 server/demo_seed.py chemin.db"""
import os, random, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import app

db = sys.argv[1] if len(sys.argv) > 1 else os.path.join(app.HERE, "demo.db")
os.environ["DB_PATH"] = db
st = app.Store(db, app.load_salt())
random.seed(7)
players = [(1000 + i, n) for i, n in enumerate(["Nova", "Kairo", "Mila", "Zed", "Ryu", "Luna", "Axel", "Sora"])]
scripts = ["yslemHub", "yslemEgg_InstantTP", "yslemEgg_DeliveryStop", "yslempet_EggTP"]
now = int(time.time())
for uid, name in players:
    st.cache_name(uid, name)
    st.new_key(uid, random.choice([7, 30, 90]), "demo")
for _ in range(400):
    uid, _n = random.choice(players)
    sc = random.choice(scripts)
    status = random.choices(["valid", "invalid", "expired", "revoked"], [86, 8, 4, 2])[0]
    ts = now - int(random.random() ** 2 * 86400 * 2)
    st.db.execute("INSERT INTO events(ts,user_id,script,game,v,status,fp,ip,owner_id) VALUES(?,?,?,?,?,?,?,?,?)",
                  (ts, uid, sc, "Ride a Pet" if "pet" in sc else "Steal An Egg", 1, status, "%010x" % random.getrandbits(40), "demo", uid))
for _ in range(6):
    st.db.execute("INSERT INTO events(ts,user_id,script,game,v,status,fp,ip) VALUES(?,?,?,?,?,?,?,?)",
                  (now - random.randint(10, 3000), 7777, "yslemHub", "Steal An Egg", 1, "invalid", "deadbeef01", "demo"))
st.db.commit()
print("demo ok:", db)
