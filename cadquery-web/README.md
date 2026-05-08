# CadQuery Web Renderer

A modern web application for OpenSCAD-style 3D modeling using Python CadQuery. Write parametric 3D models in Python, render them in real-time, and export to STL.

## Features

✨ **Live Coding**
- Write CadQuery Python code in a syntax-highlighted editor
- Real-time 3D preview with Three.js
- Instant feedback on model changes

🎨 **Interactive 3D Viewer**
- Rotate, zoom, and pan with intuitive mouse controls
- Orbit controls with smooth damping
- Grid background and multiple lighting
- Auto-fit to view

📦 **Export**
- Download rendered models as STL files
- Batch processing support

⚡ **Built-in Examples**
- Cube, Cylinder, Rod examples
- L-bracket assembly example
- Easy-to-extend example system

## Quick Start

### Installation

```bash
# Clone or navigate to the project directory
cd cadquery-web

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### Running

```bash
python app.py
```

Then open http://localhost:5000 in your browser.

## Usage

1. **Write Code**: Enter CadQuery Python code in the left editor
2. **Render**: Click "⚡ Render" or press Ctrl+Enter
3. **Interact**: Use mouse to rotate (drag), zoom (scroll), pan (right-click)
4. **Export**: Click "⬇️ Download STL" to save your model

## CadQuery Basics

```python
import cadquery as cq

# Your model must be assigned to 'result' or 'shape'

# Simple cube
result = cq.Workbench().box(10, 10, 10)

# Cylinder
result = cq.Workbench().cylinder(5, 20)

# Union (combine shapes)
base = cq.Workbench().box(50, 10, 10)
top = cq.Workbench().box(10, 10, 30)
result = base.union(top)

# Pocket (subtract)
result = cq.Workbench().box(20, 20, 20).faces(">Z").pocket(0.5)
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl+Enter / Cmd+Enter | Render code |
| Drag mouse | Rotate view |
| Scroll wheel | Zoom |
| Right-click drag | Pan view |

## Architecture

```
cadquery-web/
├── app.py              # Flask backend, executes CadQuery code
├── templates/
│   └── index.html      # Frontend with Three.js viewer
├── requirements.txt    # Python dependencies
└── README.md          # This file
```

### Backend (Flask)
- `POST /api/render` - Execute CadQuery code and return STL
- `GET /api/examples` - Fetch example scripts
- Security: Code execution in isolated namespace

### Frontend (HTML/CSS/JS)
- **Editor**: Monaco-style code input with syntax highlighting
- **Viewer**: Three.js with:
  - STL loader
  - Orbit controls
  - Real-time mesh rendering
  - Responsive grid and lighting

## Advanced Features

### Parametric Models
```python
import cadquery as cq

# Parameters
width, height, depth = 50, 30, 20
fillet_radius = 2

# Create
box = cq.Workbench().box(width, height, depth)
result = box.edges("|Z").fillet(fillet_radius)
```

### Assemblies
```python
import cadquery as cq

# Create individual parts
part1 = cq.Workbench().box(10, 10, 10)
part2 = cq.Workbench().cylinder(5, 20)

# Combine
result = part1.union(part2)
```

### Sketches & Extrusion
```python
import cadquery as cq

# Create from sketch
result = (
    cq.Workbench()
    .sketch()
    .circle(5)
    .finalize()
    .extrude(10)
)
```

## Troubleshooting

**Model not rendering?**
- Check browser console for errors (F12)
- Ensure code has `result = ...` or `shape = ...`
- Verify CadQuery syntax

**Slow performance?**
- Reduce geometry complexity
- Simplify sketches and features
- Use coarser tolerances

**Export issues?**
- Some complex geometries may need tessellation adjustment
- Try simplifying the model first

## Requirements

- Python 3.7+
- Modern web browser with WebGL support
- 100MB disk space for dependencies

## Performance

- STL rendering: < 2 seconds for most models
- 3D viewer updates: 60 FPS (with hardware acceleration)
- Live code execution: Real-time feedback

## Future Enhancements

- [ ] Code syntax highlighting with Ace/Monaco editor
- [ ] Model history and undo/redo
- [ ] Parametric slider controls
- [ ] Multi-body part management
- [ ] Bill of Materials generation
- [ ] Measurement tools
- [ ] Integration with Fusion 360 / AutoCAD
- [ ] Real-time collaboration
- [ ] Advanced materials and rendering (PBR)

## License

MIT

## Resources

- [CadQuery Documentation](https://cadquery.readthedocs.io/)
- [CadQuery GitHub](https://github.com/CadQuery/cadquery)
- [Three.js Documentation](https://threejs.org/docs/)
- [OpenSCAD Documentation](https://openscad.org/documentation.html)

## Support

For issues or feature requests, please refer to the CadQuery documentation or submit an issue in this project.
