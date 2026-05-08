#!/usr/bin/env python3
"""
CadQuery Web Renderer - Modern OpenSCAD-style 3D modeling in Python
Write CadQuery scripts, render to 3D STL, visualize with Three.js
"""

from flask import Flask, render_template, request, jsonify
import cadquery as cq
import tempfile
import os
import base64
from pathlib import Path

app = Flask(__name__)

# Store temporary files
UPLOAD_FOLDER = tempfile.gettempdir()
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/render', methods=['POST'])
def render():
    """
    Receive CadQuery Python code, execute it, and return STL as base64
    """
    try:
        data = request.get_json()
        code = data.get('code', '')
        
        if not code.strip():
            return jsonify({'error': 'No code provided'}), 400
        
        # Create a namespace with CadQuery pre-imported
        namespace = {
            'cq': cq,
            'cadquery': cq,
            '__builtins__': __builtins__,
        }
        
        # Execute user code
        exec(code, namespace)
        
        # Look for 'result' or 'shape' in the namespace
        shape = namespace.get('result') or namespace.get('shape')
        
        if shape is None:
            return jsonify({'error': 'No result or shape variable found. Assign your workbench to "result" or "shape".'}), 400
        
        # Export to STL
        stl_file = os.path.join(UPLOAD_FOLDER, 'model.stl')
        
        # Handle both CadQuery Workbench objects and raw shapes
        if hasattr(shape, 'val'):  # CadQuery workbench
            # Get the underlying shape and export as STL
            shape.val().save(stl_file)
        else:
            # Try to save directly if it's already a solid
            try:
                shape.save(stl_file)
            except:
                return jsonify({'error': 'Could not export shape to STL. Ensure result is a valid CadQuery object.'}), 400
        
        # Read STL and encode as base64
        with open(stl_file, 'rb') as f:
            stl_data = f.read()
        
        import base64
        stl_b64 = base64.b64encode(stl_data).decode('utf-8')
        
        return jsonify({
            'success': True,
            'stl': stl_b64,
            'message': 'Model rendered successfully'
        })
    
    except Exception as e:
        return jsonify({'error': str(e)}), 400

@app.route('/api/examples', methods=['GET'])
def get_examples():
    """Return example CadQuery scripts"""
    examples = {
        'cube': {
            'name': 'Simple Cube',
            'code': '''# Create a 10mm cube
result = cq.Workbench().box(10, 10, 10)
'''
        },
        'cylinder': {
            'name': 'Cylinder',
            'code': '''# Create a cylinder with radius 5mm, height 20mm
result = cq.Workbench().cylinder(5, 20)
'''
        },
        'threaded_rod': {
            'name': 'Threaded Rod',
            'code': '''# Create a simple rod
result = cq.Workbench().cylinder(5, 30)
'''
        },
        'bracket': {
            'name': 'L-Bracket',
            'code': '''# Create an L-shaped bracket
w = cq.Workbench()
base = w.box(50, 10, 10)  # Horizontal base
vertical = w.box(10, 10, 30)  # Vertical part
result = base.union(vertical)
'''
        }
    }
    return jsonify(examples)

if __name__ == '__main__':
    print("🔧 CadQuery Web Renderer")
    print("📍 Open http://localhost:5000")
    app.run(debug=True, port=5000)
