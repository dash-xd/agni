#!/usr/bin/env python3
"""Exercise pinned webhook roles against Agni's existing startup-profile graph."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

webhook = load("agni_webhook_profile", os.environ["AGNI_PROBOT_PROFILE_RENDERER"])
startup = load("agni_startup_profile", os.environ["AGNI_PROBOT_STARTUP_RENDERER"])

HASH = "a" * 32
REV = "b" * 40
STORE = "/nix/store/" + HASH + "-fixture"

def fixture():
    spec = dict(schema=1,scope="fatline-arm-vm1",home="/home/wisp",
                bundle=STORE,port=16379,archive=STORE,
                redis=STORE+"/bin/redis-server",nginx=STORE+"/bin/nginx",
                logma=STORE+"/bin/api",skymill=STORE+"/bin/skymill-http",
                probe=STORE+"/bin/fatline-services-probe",aclDigest="c"*64)
    names={"skymill":"skymill-http","logma":"logma-lifecycle","probot-runtime":"probot"}
    artifacts=dict(schema=1,system="aarch64-linux",ghxd_credentials_included=False,
                   node=STORE+"/bin/node",artifacts={
                     role:{"revision":REV,"store":"/nix/store/"+HASH+"-"+basename}
                     for role,basename in names.items()})
    sources={"schema":1,"scenario":"probot-webhook",
             "sources":{role:{"revision":REV} for role in names}}
    return spec, artifacts, sources

class WebhookProfile(unittest.TestCase):
    def test_exact_five_role_graph_and_secret_separation(self):
        spec, artifacts, sources = fixture()
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            webhook.render(spec,artifacts,sources,root,startup.render)
            self.assertIn("profile_roles=\'redis nginx logma skymill probot\'", (root/"profile.env").read_text())
            self.assertIn("profile_roles='redis nginx logma skymill probot'", (root/"profile.env").read_text().splitlines())
            units=list(root.glob("*.container"))
            self.assertEqual(len(units),5)
            redis=(root/"fatline-arm-vm1-redis.container").read_text()
            self.assertIn("Upholds=fatline-arm-vm1-nginx.service fatline-arm-vm1-logma.service fatline-arm-vm1-skymill.service fatline-arm-vm1-probot.service",redis)
            self.assertIn("/bootstrap.sh start ",redis)
            skymill=(root/"fatline-arm-vm1-skymill.container").read_text()
            self.assertIn("Environment=REDIS_ADDR=redis-proxy:6379",skymill)
            self.assertIn("Environment=REDIS_DB=0",skymill)
            self.assertIn("Environment=SKYMILL_STREAM=github.webhooks",skymill)
            self.assertNotIn("REDIS_PASSWORD_FILE=",skymill)
            self.assertIn("cat /run/credentials/redis",skymill)
            self.assertIn("SKYMILL_HTTP_TOKEN_FILE=/run/credentials/http-token",skymill)
            logma=(root/"fatline-arm-vm1-logma.container").read_text()
            self.assertIn(artifacts["artifacts"]["logma"]["store"],logma)
            self.assertIn("API_KEY=",logma)
            probot=(root/"fatline-arm-vm1-probot.container").read_text()
            self.assertIn("REDIS_PASSWORD_FILE=/run/credentials/state",probot)
            self.assertIn("cat /run/credentials/skymill-token",probot)
            self.assertNotIn("Environment=SKYMILL_TOKEN=",probot)
            self.assertIn("LOGMA_REDIS_PASSWORD_FILE=/run/credentials/publish",probot)
            self.assertIn("PROBOT_RUNTIME_WORKER_ENABLED=false",probot)
            self.assertIn("Environment=REDIS_DB=0",probot)
            self.assertIn("Environment=REDIS_PREFIX=xd-dash:fatline:runtime:probot-runtime:probot-test",probot)
            self.assertNotIn("PublishPort=",probot)
            for role in ("logma","skymill","probot"):
                unit=(root/("fatline-arm-vm1-"+role+".container")).read_text()
                self.assertIn("Volume=/var/mnt/nixstore:/nix/store:ro",unit)
                self.assertIn("ReadOnly=true",unit)
                self.assertNotIn("Environment=REDIS_PASSWORD=",unit)
            self.assertIn("aclfile /run/bootstrap-acl/users.acl",(root/"redis.conf").read_text())

    def test_unpinned_or_oauth_artifacts_rejected(self):
        spec, artifacts, sources = fixture()
        with tempfile.TemporaryDirectory() as temp:
            artifacts["ghxd_credentials_included"]=True
            with self.assertRaises(ValueError):
                webhook.render(spec,artifacts,sources,Path(temp),startup.render)
        _, artifacts, sources=fixture()
        artifacts["artifacts"]["skymill"]["revision"]="0"*40
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(ValueError):
                webhook.render(spec,artifacts,sources,Path(temp),startup.render)

if __name__ == "__main__":
    unittest.main()
