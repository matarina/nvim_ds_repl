import threading
import os
from textwrap import dedent
from IPython import get_ipython
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import atexit
import io
import sys
import inspect
import types
import json
from collections import Counter, defaultdict

ipython = get_ipython()
httpd = None  # Global reference to the server


# Ensure that if needed, the dependent libraries are imported.
try:
    import pandas as pd
except ImportError:
    pd = None

try:
    import numpy as np
except ImportError:
    np = None

try:
    import torch
except ImportError:
    torch = None

# --- Begin UniversalInspector definition (helper class) ---
class UniversalInspector:
    def __init__(self):
        self.output_lines = []

    def _format_line(self, attr_name: str, value) -> str:
        return f"{attr_name:<15}║ {value}"

    def _content_line(self, attr_name: str, value) -> str:
        return f"{'▶' * 4}\n{value}"

    def _add_line(self, line: str):
        self.output_lines.append(line)

    def _add_section(self, content: list):
        for line in content:
            self._add_line(str(line))

    def _inspect_basic_type(self, obj):
        basic_info = [
            self._format_line("Type", type(obj).__name__),
            self._format_line("Memory", f"{sys.getsizeof(obj)} bytes")
        ]
        if isinstance(obj, (str, bytes, list, tuple, set, dict)):
            try:
                basic_info.append(self._format_line("Length", len(obj)))
            except Exception as e:
                basic_info.append(self._format_line("Length", f"Error: {e}"))
        if isinstance(obj, (str, bytes, list, tuple, set)):
            try:
                basic_info.append(self._format_line("Count", dict(Counter(obj))))
            except Exception:
                pass
        basic_info.append(self._content_line("DataContent", repr(obj)))
        self._add_section(basic_info)

    def _inspect_pandas_series(self, obj):
        series_info = [
            self._format_line("Type", "Pandas Series"),
            self._format_line("Length", len(obj)),
            self._format_line("Dtype", obj.dtype),
            self._format_line("Name", obj.name),
            self._format_line("Memory", f"{obj.memory_usage(deep=True)} bytes"),
            self._format_line("Null Count", obj.isnull().sum()),
            self._format_line("Unique", obj.is_unique),
        ]
        series_info.append(self._format_line("Head", obj.head(10).to_dict()))
        self._add_section(series_info)

    def _inspect_pandas_index(self, obj):
        index_info = [
            self._format_line("Type", type(obj).__name__),
            self._format_line("Length", len(obj)),
            self._format_line("Dtype", obj.dtype),
            self._format_line("Name", obj.name),
            self._format_line("Memory", f"{obj.memory_usage()} bytes"),
            self._format_line("Is Unique", obj.is_unique),
        ]
        index_info.append(self._format_line("DataContent", list(obj)))
        self._add_section(index_info)

    def _inspect_pandas_dataframe(self, obj):
        # Get basic DataFrame info
        df_info = [
            self._format_line("Type", "Pandas DataFrame"),
            self._format_line("Shape", f"{obj.shape[0]} rows × {obj.shape[1]} columns"),
            self._format_line("Memory", f"{obj.memory_usage(deep=True).sum()} bytes"),
            self._format_line("Columns", list(obj.columns)),
            self._format_line("Dtypes", obj.dtypes.to_dict()),
            "\nData Content:"
        ]
        self._add_section(df_info)
        # For brevity, include only a small preview table.
        preview = obj.head(10).to_string()
        self._add_line(preview)

    def _inspect_class_or_instance(self, obj):
        is_class = inspect.isclass(obj)
        cls = obj if is_class else obj.__class__
        basic_info = [
            self._format_line("Type", "Class" if is_class else "Instance"),
            self._format_line("Name", cls.__name__),
            self._format_line("Module", cls.__module__),
            self._format_line("Base classes", [base.__name__ for base in cls.__bases__])
        ]
        self._add_section(basic_info)
        attrs = defaultdict(list)
        for name, value in inspect.getmembers(obj):
            if name.startswith('__'):
                continue
            if inspect.ismethod(value) or inspect.isfunction(value):
                attrs['Methods'].append((name, value))
            elif isinstance(value, property):
                attrs['Properties'].append((name, value))
            elif isinstance(value, (staticmethod, classmethod)):
                attrs['Class/Static Methods'].append((name, value))
            else:
                attrs['Attributes'].append((name, value))
        for category, items in attrs.items():
            if items:
                category_info = [f"\n{category}:"]
                for name, value in sorted(items, key=lambda x: x[0]):
                    try:
                        if inspect.ismethod(value) or inspect.isfunction(value):
                            sig = inspect.signature(value)
                            doc = value.__doc__ and value.__doc__.strip()
                            info = f"  {name}{sig}"
                            if doc:
                                info += f"\n    Doc: {doc}"
                        else:
                            info = f"  {name}: {type(value).__name__} = {repr(value)}"
                    except Exception as e:
                        info = f"  {name}: <Error: {str(e)}>"
                    category_info.append(info)
                self._add_section(category_info)

    def _inspect_function(self, obj):
        func_info = [
            self._format_line("Type", "Function"),
            self._format_line("Name", obj.__name__),
            self._format_line("Module", obj.__module__),
            self._format_line("Signature", str(inspect.signature(obj))),
            self._format_line("Docstring", (obj.__doc__ or "<No docstring>").strip())
        ]
        self._add_section(func_info)
        try:
            source = inspect.getsource(obj)
            self._add_section(["Source Code:", source])
        except Exception:
            pass

    def _inspect_numpy_array(self, obj):
        array_info = [
            self._format_line("Type", "NumPy Array"),
            self._format_line("Shape", obj.shape),
            self._format_line("Dtype", obj.dtype),
            self._format_line("Size", obj.size),
            self._format_line("NDim", obj.ndim),
            self._content_line("DataContent", str(obj))
        ]
        self._add_section(array_info)

    def _inspect_torch_tensor(self, obj):
        tensor_info = [
            self._format_line("Type", "PyTorch Tensor"),
            self._format_line("Shape", obj.shape),
            self._format_line("Dtype", obj.dtype),
            self._format_line("Device", obj.device),
            self._format_line("Requires Grad", obj.requires_grad),
            self._content_line("DataContent", str(obj))
        ]
        self._add_section(tensor_info)

    def inspect(self, obj) -> str:
        self.output_lines = []
        # For objects defined in __main__, show class/instance details.
        if (inspect.isclass(obj) and obj.__module__ == '__main__') or (
            not inspect.isclass(obj) and obj.__class__.__module__ == '__main__'):
            self._inspect_class_or_instance(obj)
        elif inspect.isfunction(obj) or inspect.ismethod(obj):
            self._inspect_function(obj)
        elif pd is not None and isinstance(obj, pd.Series):
            self._inspect_pandas_series(obj)
        elif pd is not None and hasattr(obj, 'dtype') and hasattr(obj, 'is_unique') and not hasattr(obj, 'to_json'):
            # A simple check for a Pandas Index
            self._inspect_pandas_index(obj)
        elif np is not None and isinstance(obj, np.ndarray):
            self._inspect_numpy_array(obj)
        elif torch is not None and isinstance(obj, torch.Tensor):
            self._inspect_torch_tensor(obj)
        elif pd is not None and isinstance(obj, pd.DataFrame):
            self._inspect_pandas_dataframe(obj)
        else:
            self._inspect_basic_type(obj)
        return "\n".join(self.output_lines)
# --- End UniversalInspector definition ---

def query_object_info(obj):
    """
    Query detailed information about a Python object and return it as a JSON string.

    Parameters:
      - obj: The object to inspect.

    Returns:
      - json_str: A JSON string containing the type and data of the object.
    """
    response = {}

    # Handle a few specific cases for consistent output formats
    if pd is not None and isinstance(obj, pd.DataFrame):
        # For DataFrame, we preserve a simple JSON view
        response['type'] = 'dataframe'
        try:
            response['data'] = obj.to_json(orient='records')
        except Exception as e:
            response['data'] = f"Error converting DataFrame to JSON: {e}"
    elif pd is not None and isinstance(obj, pd.Series):
        inspector = UniversalInspector()
        inspector._inspect_pandas_series(obj)
        response['type'] = 'pandas_series'
        response['data'] = "\n".join(inspector.output_lines)
    elif np is not None and isinstance(obj, np.ndarray):
        inspector = UniversalInspector()
        inspector._inspect_numpy_array(obj)
        response['type'] = 'numpy_array'
        response['data'] = "\n".join(inspector.output_lines)
    elif torch is not None and isinstance(obj, torch.Tensor):
        inspector = UniversalInspector()
        inspector._inspect_torch_tensor(obj)
        response['type'] = 'torch_tensor'
        response['data'] = "\n".join(inspector.output_lines)
    elif inspect.isfunction(obj) or inspect.ismethod(obj):
        inspector = UniversalInspector()
        inspector._inspect_function(obj)
        response['type'] = 'function'
        response['data'] = "\n".join(inspector.output_lines)
    elif inspect.isclass(obj):
        inspector = UniversalInspector()
        inspector._inspect_class_or_instance(obj)
        response['type'] = 'class'
        response['data'] = "\n".join(inspector.output_lines)
    else:
        # Default handler uses the basic type inspector.
        inspector = UniversalInspector()
        inspector._inspect_basic_type(obj)
        response['type'] = 'info'
        response['data'] = "\n".join(inspector.output_lines)

    return json.dumps(response)


# Define the HTTP request handler
class GlobalEnvHandler(BaseHTTPRequestHandler):

    def _set_headers(self, content_type='application/json'):
        """Helper method to set the headers."""
        self.send_response(200)
        self.send_header('Content-type', content_type)
        self.end_headers()

    def capture_output(self, func):
        """Capture the stdout output of a function."""
        captured_output = io.StringIO()
        original_stdout = sys.stdout
        try:
            sys.stdout = captured_output
            func()
            output = captured_output.getvalue()
        finally:
            sys.stdout = original_stdout
        
        return output

    def do_GET(self):
        """Handle GET requests."""
        # Parse the path to determine what action to take
        if self.path == '/query_global':
            self.query_global()
        elif self.path.startswith('/inspect_var'):
            var_name = self.path.split('=')[-1]
            self.inspect_var(var_name)
        else:
            self.send_error(404, "Path not found")

    def query_global(self):
        """Retrieve and return the list of global variables."""
        global_vars = self.capture_output(lambda: ipython.run_line_magic("whos", ""))
        self._set_headers()
        # Convert the output to JSON string
        self.wfile.write(json.dumps({"globals": global_vars}, default=str).encode('utf-8'))

    def inspect_var(self, var_name):
        """Inspect a specific variable by name."""
        try:
            var = globals().get(var_name, None)
            if var is None:
                self.send_error(400, f"Variable '{var_name}' not found.")
                return

            var_info = query_object_info(var)
            self._set_headers()
            self.wfile.write(json.dumps({"info": var_info}, default=str).encode('utf-8'))
        except Exception as e:
            self.send_error(400, f"Error inspecting variable: {e}")

def start_http_server(port):
    global httpd
    server_address = ('', port)
    httpd = HTTPServer(server_address, GlobalEnvHandler)
    print(f"Starting server on port {port}")
    httpd.serve_forever()


def stop_http_server():
    global httpd
    if httpd:
        print("Shutting down server...")
        httpd.shutdown()
        httpd.server_close()
        print("Server shut down.")

# Register the shutdown function to be called on exit
atexit.register(stop_http_server)

def init_python_server(port):
    server_thread = threading.Thread(target=start_http_server, args=(port,))
    server_thread.daemon = True  # Ensure the thread exits when the main program exits
    server_thread.start()

if __name__ == "__main__":
    if len(sys.argv) > 1:
        port = int(sys.argv[1])
        init_python_server(port)
    else:
        print("Please provide a port number as an argument.")

