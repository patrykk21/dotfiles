#!/bin/bash
# Test script for tmux fixes

echo "=== Tmux Configuration Test ==="
echo
echo "1. PANE MODE FIX TEST:"
echo "   - Press Ctrl+Shift+P to enter pane mode"
echo "   - Press 'n' - should create a new PANE below (not a new tab)"
echo "   - Press 's' - should create horizontal split"
echo "   - Press 'v' - should create vertical split"
echo
echo "2. SESSION MODE ENHANCEMENTS TEST:"
echo "   - Press Ctrl+Shift+O to enter session mode"
echo "   - Press 'c' - prompts for new session name"
echo "   - Press 'n' - creates auto-named session"
echo "   - Press 'w' - shows session chooser (or message if only 1 session)"
echo "   - Press 'l' - lists all sessions"
echo "   - Press 'x' - kills current session (with confirmation)"
echo "   - Press 'r' - rename current session"
echo "   - Press '1/2/3' - switch to session by number"
echo
echo "3. CREATING TEST SESSIONS:"
tmux list-sessions 2>/dev/null || echo "No tmux sessions running"
echo
echo "Creating test sessions..."
tmux new-session -d -s "test-work" 2>/dev/null && echo "✓ Created session: test-work"
tmux new-session -d -s "test-personal" 2>/dev/null && echo "✓ Created session: test-personal"
tmux new-session -d -s "test-admin" 2>/dev/null && echo "✓ Created session: test-admin"
echo
echo "Current sessions:"
tmux list-sessions 2>/dev/null || echo "No sessions found"
echo
echo "To attach to tmux and test: tmux attach"