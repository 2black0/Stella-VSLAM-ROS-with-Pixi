# libOpenGL.so Missing - Root Cause & Fix

## Problem Summary

Build fails with:
```
error: cannot find -lOpenGL
/usr/bin/ld: cannot find -lOpenGL: No such file or directory
```

Despite OpenGL libraries being installed in the Pixi environment.

## Root Cause Analysis

The Pixi environment had:
- ✅ `libOpenGL.so.0` (versioned symlink → `libOpenGL.so.0.0.0`)
- ✅ `libOpenGL.so.0.0.0` (actual library file)
- ❌ **`libOpenGL.so` (unversioned symlink) - MISSING**

**Why this broke:**
- CMake's `find_package(OpenGL)` explicitly looks for the unversioned `libOpenGL.so`
- Conda packages `libgl-devel` includes only versioned `.so.0` files
- The unversioned symlink must be created manually

## The Fix

### Immediate Fix (Manual)
```bash
ln -sf libOpenGL.so.0 $CONDA_PREFIX/lib/libOpenGL.so
```

### Permanent Fix (Script Changes)

Modified `scripts/build-deps.sh` to create OpenGL symlinks **before building** (not just during Pangolin):

**Added at line 106-120:**
```bash
# Ensure OpenGL symlinks exist BEFORE building anything
# This is critical for CMake to find libOpenGL.so (unversioned)
echo "Ensuring OpenGL/EGL symlinks in Pixi environment..."
ensure_gl_symlink() {
    local link_path="$1"
    local target_path="$2"
    if [ ! -e "$link_path" ] && [ -e "$target_path" ]; then
        ln -s "$(basename "$target_path")" "$link_path"
        echo "  Created: $(basename "$link_path") -> $(basename "$target_path")"
    elif [ -e "$link_path" ]; then
        echo "  OK: $(basename "$link_path") already exists"
    else
        echo "  WARNING: Target $(basename "$target_path") not found"
    fi
}

ensure_gl_symlink "$CONDA_PREFIX/lib/libOpenGL.so" "$CONDA_PREFIX/lib/libOpenGL.so.0"
ensure_gl_symlink "$CONDA_PREFIX/lib/libEGL.so" "$CONDA_PREFIX/lib/libEGL.so.1"
```

**Removed duplicate:** Pangolin section (lines 179-191) no longer redefines `ensure_gl_symlink`

## Technical Details

### Symlink Chain

Before fix:
```
libOpenGL.so         (MISSING)
libOpenGL.so.0  ──→  libOpenGL.so.0.0.0 (✓ exists)
```

After fix:
```
libOpenGL.so   ──→  libOpenGL.so.0 ──→  libOpenGL.so.0.0.0 (✓)
```

### Why GLVND?

The CMakeLists use `set(OpenGL_GL_PREFERENCE GLVND)` which:
- Looks for separate `libGL.so` and `libOpenGL.so` (NVIDIA GLVND model)
- NOT the legacy unified `libGL.so` approach
- Both must be present for proper linking

### Related Files

| File | Change |
|------|--------|
| `scripts/build-deps.sh` | Added early symlink creation, removed duplicate function |
| `scripts/check-opengl-symlinks.sh` | NEW: Diagnostic script to verify symlinks |
| `lib/iridescence/CMakeLists.txt` | Line 19: `set(OpenGL_GL_PREFERENCE GLVND)` |
| `lib/Pangolin/cmake/*` | Uses `find_package(OpenGL)` which requires unversioned symlinks |

## Verification

After fix, verify with:
```bash
pixi shell
bash scripts/check-opengl-symlinks.sh
```

Expected output:
```
✓ libOpenGL.so → libOpenGL.so.0
✓ libEGL.so → libEGL.so.1.1.0
```

## Timeline

1. **Environment setup**: Pixi installs `libgl-devel` with versioned libraries only
2. **Before fix**: Building Pangolin or Iridescence would fail at CMake configuration stage
3. **With fix**: Symlinks are created early in `build-deps.sh`, before any CMake invocation

## Prevention

- Always run `pixi run build-deps` before `pixi run build`
- Check symlinks with `bash scripts/check-opengl-symlinks.sh` after `pixi shell`
- The fixed script now prevents this automatically
