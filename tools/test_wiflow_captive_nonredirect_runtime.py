"""Execute the production Website/Image/Video confirmation JS in isolated Node VMs.

This is browser-logic evidence only, not a captive mini-browser/device test.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest

BASE = Path(__file__).resolve().parents[1] / "package/wiflow-setup/files/www-wiflow-portal"

JS_HARNESS = r"""
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync(0,'utf8');
const test=process.argv[1];
const errors=[];
const calls=[];
const status=(code,allowed=false)=>({status:code,json:async()=>({ok:true,authorized:allowed})});
const reply=async(url,options)=>{
  calls.push({url,options});
  if(test==='network_ok')return status(204);
  if(test==='status_true')return calls.length===1?status(409):status(200,true);
  if(test==='status_false')return calls.length===1?status(409):status(200,false);
  if(test==='first_disconnected'){
    if(calls.length===1)throw new Error('captive mini-browser network reset');
    return status(200,true);
  }
  if(test==='network_failed')throw new Error('no response');
  throw new Error('unexpected call');
};
const target='http://10.10.10.1:2080/cgi-bin/portal';
const ctx={
  state:'ready',
  preview:test==='preview',
  sessionId:'abcdef1234567890abcdef12',
  authorizeUrl:target,
  window:{location:{
    origin:test==='foreign_origin'?'http://example.com':'http://10.10.10.1:2080',
    href:test==='foreign_origin'?'http://example.com/test':target
  },fetch:reply},
  URL,URLSearchParams,
  validRuntime(){return true;},
  access:{disabled:false,setAttribute(){ }},
  confirm:{disabled:false},
  dialog:{hidden:false,setAttribute(){ }},
  runtimeError:{hidden:true,textContent:''},
  stopAutoSlider(){},
  closeDialog(){ctx.dialog.hidden=true;},
  setError(message){ctx.state='error';ctx.runtimeError.textContent=message;}
};
vm.createContext(ctx);
(async()=>{
  vm.runInContext(source+'; globalThis.testCommit=commit;',ctx,{timeout:4000});
  await ctx.testCommit();
  console.log(JSON.stringify({state:ctx.state,
    calls, accessDisabled:ctx.access.disabled, confirmDisabled:ctx.confirm.disabled,
    dialogHidden:ctx.dialog.hidden, statusText:ctx.runtimeError.textContent,
    statusHidden:ctx.runtimeError.hidden}));
})().catch(e=>{console.error(e.stack);process.exit(1);});
"""


class CaptiveNonredirectRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.node = shutil.which("node")
        if not cls.node:
            raise RuntimeError("Node.js required for executed captive Portal JS contract tests")

    def run_one(self, mode, scenario):
        html = (BASE / f"template-{mode}.html").read_text()
        anchor = "  const commit=async()=>{"
        start = html.index(anchor)
        end = html.index("\n\n  access.disabled=true;", start)
        js = html[start:end]
        result = subprocess.run(
            [self.node, "-e", JS_HARNESS, scenario], input=js,
            text=True, capture_output=True, timeout=6,
            env={**os.environ, "TZ": "UTC"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_confirmation_success_never_navigates_all_modes(self):
        for mode in ("website", "image", "video"):
            with self.subTest(mode=mode):
                r = self.run_one(mode, "network_ok")
                self.assertEqual(r["state"], "authorized")
                self.assertEqual(len(r["calls"]), 1)
                call = r["calls"][0]
                self.assertEqual(call["url"], "http://10.10.10.1:2080/cgi-bin/portal")
                self.assertEqual(call["options"]["method"], "POST")
                self.assertEqual(call["options"]["credentials"], "same-origin")
                self.assertEqual(call["options"]["mode"], "same-origin")
                self.assertEqual(call["options"]["redirect"], "error")
                self.assertIn("action=authorize", call["options"]["body"])
                self.assertTrue(r["dialogHidden"])
                self.assertTrue(r["accessDisabled"])
                self.assertIn("Đã xác nhận", r["statusText"])

    def test_ambiguous_post_uses_actual_session_status(self):
        for case in ("status_true", "first_disconnected"):
            for mode in ("website", "image", "video"):
                with self.subTest(mode=mode, case=case):
                    r = self.run_one(mode, case)
                    self.assertEqual(r["state"], "authorized")
                    self.assertEqual(len(r["calls"]), 2)
                    self.assertIn("action=status", r["calls"][1]["options"]["body"])

    def test_failed_status_does_not_claim_internet(self):
        for case in ("status_false", "network_failed"):
            for mode in ("website", "image", "video"):
                with self.subTest(mode=mode, case=case):
                    r = self.run_one(mode, case)
                    self.assertEqual(r["state"], "ready")
                    self.assertFalse(r["accessDisabled"])
                    self.assertFalse(r["confirmDisabled"])
                    self.assertEqual(len(r["calls"]), 2)
                    self.assertIn("Chưa xác nhận", r["statusText"])

    def test_preview_never_authorizes(self):
        for mode in ("website", "image", "video"):
            with self.subTest(mode=mode):
                r = self.run_one(mode, "preview")
                self.assertEqual(r["state"], "ready")
                self.assertEqual(r["calls"], [])

    def test_foreign_origin_never_posts_session_id(self):
        for mode in ("website", "image", "video"):
            with self.subTest(mode=mode):
                r = self.run_one(mode, "foreign_origin")
                self.assertEqual(r["state"], "error")
                self.assertEqual(r["calls"], [])


if __name__ == "__main__":
    unittest.main()
