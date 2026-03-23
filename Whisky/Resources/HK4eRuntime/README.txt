This folder is a placeholder for HK4e runtime assets used by the integrated HK4e launch mode.

Expected layout (either form is accepted):

1) Flat layout
   HK4eRuntime/
     dxmt/
       d3d10core.dll
       d3d11.dll
       dxgi.dll
       winemetal.dll
       winemetal.so
     protonextras/
       steam64.exe
       steam32.exe
       lsteamclient64.dll
       lsteamclient32.dll

2) yaaglwdos-compatible layout
   HK4eRuntime/
     dxmt/
       (same as above)
     sidecar/protonextras/
       (same as above)

If you don't want to bundle these files, you can set the environment variable:
  HK4E_RUNTIME_ROOT=<path>
Point it at a directory containing dxmt/ and either protonextras/ or sidecar/protonextras/.
