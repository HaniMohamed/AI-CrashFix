from __future__ import annotations

from app.utils.gitlab_url import (
    derive_gitlab_project_path_from_repo_url,
    derive_gitlab_server_url_from_repo_url,
)


def test_derive_gitlab_server_url_https() -> None:
    assert (
        derive_gitlab_server_url_from_repo_url(
            "https://gitlab.gosi.ins/super-app/gosi-super-app"
        )
        == "https://gitlab.gosi.ins"
    )


def test_derive_gitlab_server_url_https_git_suffix() -> None:
    assert (
        derive_gitlab_server_url_from_repo_url(
            "https://gitlab.gosi.ins/super-app/gosi-super-app.git"
        )
        == "https://gitlab.gosi.ins"
    )


def test_derive_gitlab_server_url_ssh() -> None:
    assert (
        derive_gitlab_server_url_from_repo_url(
            "git@gitlab.gosi.ins:super-app/gosi-super-app.git"
        )
        == "https://gitlab.gosi.ins"
    )


def test_derive_gitlab_project_path() -> None:
    assert (
        derive_gitlab_project_path_from_repo_url(
            "https://gitlab.gosi.ins/super-app/gosi-super-app"
        )
        == "super-app/gosi-super-app"
    )
