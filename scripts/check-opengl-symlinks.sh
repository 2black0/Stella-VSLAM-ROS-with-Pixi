#!/bin/bash
if [ -z "$CONDA_PREFIX" ]; then
    echo "ERROR: Not in Pixi environment. Run 'pixi shell' first."
    exit 1
fi

echo "=== OpenGL/EGL Symlink Status in $CONDA_PREFIX ==="
echo ""
echo "CRITICAL for CMake builds:"
for lib in libOpenGL libEGL; do
    unversioned="$CONDA_PREFIX/lib/${lib}.so"
    
    if [ -e "$unversioned" ]; then
        target=$(readlink "$unversioned" 2>/dev/null || echo "(regular file)")
        echo "✓ ${lib}.so → $target"
    else
        versioned=$(ls "$CONDA_PREFIX/lib/${lib}.so."* 2>/dev/null | head -1)
        if [ -n "$versioned" ]; then
            echo "✗ ${lib}.so MISSING! (but versioned exists: $(basename $versioned))"
            echo "  FIX: ln -sf $(basename $versioned) $unversioned"
        else
            echo "✗ ${lib}.so MISSING! (no versioned lib found either)"
        fi
    fi
done

echo ""
echo "All OpenGL/EGL libs:"
ls -1 "$CONDA_PREFIX/lib"/libGL* "$CONDA_PREFIX/lib"/libEGL* 2>/dev/null | xargs -I {} basename {} | sort
