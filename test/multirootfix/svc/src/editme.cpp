// editme.cpp — the MCP multi-root EDIT gate fixture (DESIGN_multiRoot.md A11). shared_edit_target is
// defined in BOTH roots with the SAME name: a `paths[]` edit must refuse it UNLESS the request carries
// the root-labeled path form (file:"svc/"), then write svc's REAL disk file. svc_unique_target exists in
// svc only → it resolves unambiguously across the workspace with no label.
int shared_edit_target()
{
    return 100;
}

int svc_unique_target()
{
    return 200;
}
