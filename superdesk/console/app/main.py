"""super控制台 -- self-hosted management console + RustDesk-compatible API for super远程桌面."""
import logging
import os

from fastapi import FastAPI, Request
from fastapi.exceptions import HTTPException as FastAPIHTTPException
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from . import admin_api, db, rd_api, sd_api, security

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

app = FastAPI(title="super控制台", docs_url=None, redoc_url=None, openapi_url=None)


@app.exception_handler(FastAPIHTTPException)
async def http_error(request: Request, exc: FastAPIHTTPException):
    # RustDesk clients read {"error": "..."}; the admin UI reads it too.
    return JSONResponse({"error": exc.detail if isinstance(exc.detail, str) else str(exc.detail)},
                        status_code=exc.status_code, headers=getattr(exc, "headers", None))


@app.on_event("startup")
def startup():
    db.init()
    security.ensure_bootstrap_admin()
    admin_api.start_cleanup_thread()


app.include_router(sd_api.router)
app.include_router(admin_api.router)
app.include_router(rd_api.router)

STATIC = os.path.join(os.path.dirname(__file__), "static", "admin")
app.mount("/admin", StaticFiles(directory=STATIC, html=True), name="admin")


@app.get("/")
def root():
    return RedirectResponse("/admin/")


@app.get("/admin")
def admin_noslash():
    return RedirectResponse("/admin/")
