import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from tool.refresh_news_artifact import select_run, extract

class ArtifactTests(unittest.TestCase):
    def test_provenance(self):
        run = dict(databaseId=1,headSha='current',headBranch='main',conclusion='success',event='push')
        self.assertEqual(select_run([run], 'current'), 1)
        for changed in [dict(headSha='old'),dict(headBranch='other'),dict(conclusion='failure'),dict(event='pull_request')]:
            with self.assertRaises(ValueError):select_run([{**run,**changed}],'current')
    def test_latest_successful_refresh_extends_artifact_lifetime_without_app_rebuild(self):
        app = dict(databaseId=1,headSha='current',headBranch='main',conclusion='success',event='push',updatedAt='2026-01-01')
        refresh = dict(app,databaseId=2,event='schedule',updatedAt='2026-10-28')
        old = dict(refresh,databaseId=3,headSha='old',updatedAt='2026-10-29')
        self.assertEqual(select_run([app,refresh,old],'current'),2)
    def archive(self, path, extra=None, cached=False):
        with tarfile.open(path,'w') as t:
            files={'./index.html':'app','./version.json':'unchanged','./news.json':'{}','./shike-sw.js':'const BUILD = '+json.dumps({'resources':[{'path':'news.json'}] if cached else []})+';'}
            for name,value in files.items():
                info=tarfile.TarInfo(name);data=value.encode();info.size=len(data);t.addfile(info,io.BytesIO(data))
            if extra:t.addfile(extra)
    def test_extract_and_preserve_application(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive=Path(tmp)/'artifact.tar';dest=Path(tmp)/'web';self.archive(archive)
            extract(archive,dest)
            self.assertEqual((dest/'version.json').read_text(),'unchanged')
            with self.assertRaises(ValueError):extract(archive,dest)
    def test_unsafe_paths_links_and_precached_news_rejected(self):
        for name,kind in [('../escape',tarfile.REGTYPE),('/absolute',tarfile.REGTYPE),('link',tarfile.SYMTYPE)]:
            with tempfile.TemporaryDirectory() as tmp:
                archive=Path(tmp)/'artifact.tar';info=tarfile.TarInfo(name);info.type=kind;self.archive(archive,extra=info)
                with self.assertRaises(ValueError):extract(archive,Path(tmp)/'web')
        with tempfile.TemporaryDirectory() as tmp:
            archive=Path(tmp)/'artifact.tar';self.archive(archive,cached=True)
            with self.assertRaises(ValueError):extract(archive,Path(tmp)/'web')
