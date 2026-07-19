from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

from app.services.git_service import GitService, _repair_overlapping_hunks


OVERLAPPING_DIFF = """--- a/lib/apps/taqdeer_re/offer/srvices/offer_step_services.dart
+++ b/lib/apps/taqdeer_re/offer/srvices/offer_step_services.dart
@@ -1,5 +1,6 @@
 import 'dart:io';
 
+import 'dart:convert';
 import 'package:gosi_core/gosi_Core.dart';
 import 'package:super_app/apps/taqdeer_re/offer/model/offer_external_navigation_model.dart';
 
@@ -5,8 +6,15 @@
 
 class OfferExternalNavigationService {
   static List<OfferExternalVaigationModel> redirectionConfigList =
-      offerExternalVaigationModelFromJson(
-          RemoteConfig.taqdeerOfferExternalNavigationService.getListMap());
+      _parseRedirectionConfig();
 
+  static List<OfferExternalVaigationModel> _parseRedirectionConfig() {
+    final data = RemoteConfig.taqdeerOfferExternalNavigationService.getListMap();
+    if (data is String) {
+      return offerExternalVaigationModelFromJson(json.decode(data) as List);
+    }
+    return offerExternalVaigationModelFromJson(data ?? []);
+  }
 
   static bool isThisOfferPartOfExternalNavigation(String offerID) {
     return redirectionConfigList.any((element) => (element.offerId == offerID));
"""


ORIGINAL_FILE = """import 'dart:io';

import 'package:gosi_core/gosi_Core.dart';
import 'package:super_app/apps/taqdeer_re/offer/model/offer_external_navigation_model.dart';

class OfferExternalNavigationService {
  static List<OfferExternalVaigationModel> redirectionConfigList =
      offerExternalVaigationModelFromJson(
          RemoteConfig.taqdeerOfferExternalNavigationService.getListMap());

  static bool isThisOfferPartOfExternalNavigation(String offerID) {
    return redirectionConfigList.any((element) => (element.offerId == offerID));
  }
}
"""


def test_repair_overlapping_hunks_shifts_second_hunk() -> None:
    fixed = _repair_overlapping_hunks(OVERLAPPING_DIFF)
    headers = [ln for ln in fixed.splitlines() if ln.startswith("@@")]
    assert len(headers) == 2
    # Second hunk must not start before the first hunk ends (old line 6+).
    assert headers[1].startswith("@@ -6,") or headers[1].startswith("@@ -7,")


def test_apply_overlapping_llm_diff(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.check_output(["git", "init"], cwd=repo)
    subprocess.check_output(["git", "config", "user.email", "t@example.com"], cwd=repo)
    subprocess.check_output(["git", "config", "user.name", "t"], cwd=repo)
    target = repo / "lib/apps/taqdeer_re/offer/srvices"
    target.mkdir(parents=True)
    f = target / "offer_step_services.dart"
    f.write_text(ORIGINAL_FILE, encoding="utf-8")
    subprocess.check_output(["git", "add", "-A"], cwd=repo)
    subprocess.check_output(["git", "commit", "-m", "init"], cwd=repo)

    git = GitService(repo_root=str(repo))
    git.apply_unified_diff(OVERLAPPING_DIFF)
    text = f.read_text(encoding="utf-8")
    assert "import 'dart:convert';" in text
    assert "_parseRedirectionConfig" in text
