#!/usr/bin/env python3
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

def load(name, filename):
    spec=importlib.util.spec_from_file_location(name, filename)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

module=load("agni_probot_credentials",os.environ["AGNI_PROBOT_CREDENTIAL_GENERATOR"])
planner=load("agni_probot_acl_policy",os.environ["AGNI_PROBOT_REDIS_PLANNER"])
base_policy=Path(os.environ["AGNI_PROBOT_REDIS_BASELINE"])
renderer=Path(os.environ["AGNI_PROBOT_REDIS_RENDERER"])

class CredentialGeneration(unittest.TestCase):
    def fixture(self, folder):
        root=Path(folder)
        old=root/"old.acl"
        lines=["user default off"]
        for name in ("logma","skymill","bootstrap","publisher","subscriber"):
            lines.append("user "+name+" on #"+hashlib.sha256((name*8).encode()).hexdigest()+" -@all +ping")
        old.write_text("\n".join(lines)+"\n")
        prior=root/"prior"
        for role in module.ORIGINAL_ROLES:
            folder=prior/role
            folder.mkdir(parents=True)
            (folder/"redis").write_text(role*16+"\n")
        (prior/"logma/api-key").write_text("a"*64+"\n")
        selection={"schema":1,"scenario":"probot-webhook",
                   "sources":{name:{"revision":"b"*40} for name in ("logma","skymill","probot-runtime")}}
        policy=planner.build_policy(json.loads(base_policy.read_text()),selection,"fatline-arm-vm1")
        policy_path=root/"policy.json"
        policy_path.write_text(json.dumps(policy)+"\n")
        return old,prior,policy_path

    def test_preserves_credentials_and_separates_new_roles(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            old,prior,policy=self.fixture(root)
            target=root/"candidate"
            module.generate(policy,old,prior,target,renderer)
            acl=(target/"users.acl").read_text()
            self.assertEqual(len(acl.splitlines()),9)
            for role in module.ALL:
                self.assertEqual(sum(line.startswith("user "+role+" ") for line in acl.splitlines()),1)
            for role in ("publisher","subscriber"):
                self.assertIn(next(line for line in old.read_text().splitlines() if line.startswith("user "+role+" ")),acl)
            self.assertEqual((target/"credentials/logma/redis").read_text(),
                             (prior/"logma/redis").read_text())
            self.assertEqual((target/"credentials/logma/api-key").read_text(),"a"*64+"\n")
            self.assertEqual((target/"credentials/probot/skymill-token").read_text(),
                             (target/"credentials/skymill/http-token").read_text())
            self.assertNotEqual((target/"credentials/probot/state").read_text(),
                                (target/"credentials/probot/publish").read_text())
            for user,filename in (("probot_state","probot/state"),("lifecycle_publish","probot/publish"),
                                  ("lifecycle_subscribe","lifecycle_subscribe/redis")):
                password=(target/"credentials"/filename).read_text().strip()
                row=next(line for line in acl.splitlines() if line.startswith("user "+user+" "))
                self.assertIn("#"+hashlib.sha256(password.encode()).hexdigest(),row)
            self.assertEqual((target/"users.acl").stat().st_mode & 0o777,0o600)
            with self.assertRaises(ValueError):
                module.generate(policy,old,prior,target,renderer)

    def test_unknown_old_redis_user_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            old,prior,policy=self.fixture(root)
            with old.open("a") as f:f.write("user unexpected on +@all\n")
            with self.assertRaisesRegex(ValueError,"Unknown existing"):
                module.generate(policy,old,prior,root/"candidate",renderer)

if __name__=="__main__":
    unittest.main()
