import sys
import io
import traceback
from typing import Dict, Any, Optional
import ast
import builtins
import contextlib
from .dice_roller import DiceRoller

class CodeExecutor:
    """Utility for executing Python code safely"""
    
    # Set of allowed built-in functions
    ALLOWED_BUILTINS = {
        'abs', 'all', 'any', 'bool', 'dict', 'dir', 'enumerate', 'filter', 
        'float', 'format', 'frozenset', 'hash', 'int', 'isinstance', 'issubclass', 
        'len', 'list', 'map', 'max', 'min', 'next', 'print', 'range', 'repr', 
        'reversed', 'round', 'set', 'slice', 'sorted', 'str', 'sum', 'tuple', 'type', 'zip'
    }
    
    # Set of allowed modules
    ALLOWED_MODULES = {
        'math', 'random', 'statistics', 're', 'json', 'datetime', 'collections'
    }
    
    # Set of disallowed AST nodes (for security)
    DISALLOWED_NODES = {
        ast.Import, ast.ImportFrom, ast.ClassDef, ast.AsyncFunctionDef, 
        ast.Await, ast.AsyncFor, ast.AsyncWith
    }
    
    @staticmethod
    def is_safe_code(code: str) -> bool:
        """
        Check if the code is safe to execute
        
        Args:
            code: Python code to check
            
        Returns:
            True if the code is safe, False otherwise
        """
        try:
            # Parse the code into an AST
            tree = ast.parse(code)
            
            # Check for disallowed nodes
            for node in ast.walk(tree):
                if type(node) in CodeExecutor.DISALLOWED_NODES:
                    return False
                
                # Check for exec calls
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == 'exec':
                    return False
                
                # Check for __import__ calls
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == '__import__':
                    return False
                
                # Check for eval calls
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == 'eval':
                    return False
                
                # Check for imports in function calls
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == 'importlib':
                    return False
                
                # Check for attribute access on modules
                if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name):
                    if node.value.id == 'os' or node.value.id == 'sys' or node.value.id == 'subprocess':
                        return False
            
            return True
        
        except SyntaxError:
            return False
    
    @staticmethod
    def get_source_segment(source, node):
        """
        Get the source code segment for a node (compatible with all Python versions)
        
        Args:
            source: Source code string
            node: AST node
            
        Returns:
            Source code segment for the node
        """
        try:
            # Try to use ast.unparse if available (Python 3.9+)
            if hasattr(ast, 'unparse'):
                return ast.unparse(node)
        except:
            pass
        
        # Fallback for older Python versions
        try:
            if hasattr(node, 'lineno') and hasattr(node, 'end_lineno'):
                start = node.lineno
                end = node.end_lineno
                lines = source.splitlines()
                if start <= len(lines) and end <= len(lines):
                    if start == end:
                        return lines[start-1]
                    else:
                        return '\n'.join(lines[start-1:end])
        except:
            pass
        
        # Last resort: just return the code as is
        return source
    
    @staticmethod
    def execute_code(code: str, globals_dict: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """
        Execute Python code safely
        
        Args:
            code: Python code to execute
            globals_dict: Optional dictionary of global variables
            
        Returns:
            Dictionary containing execution results
        """
        if not CodeExecutor.is_safe_code(code):
            return {
                "success": False,
                "error": "Code contains potentially unsafe operations",
                "output": "",
                "result": None
            }
        
        # Create a restricted globals dictionary
        restricted_globals = {}
        
        # Add allowed builtins
        restricted_builtins = {name: getattr(builtins, name) for name in CodeExecutor.ALLOWED_BUILTINS if hasattr(builtins, name)}
        restricted_globals['__builtins__'] = restricted_builtins
        
        # Add DiceRoller
        restricted_globals['DiceRoller'] = DiceRoller
        
        # Add allowed modules
        for module_name in CodeExecutor.ALLOWED_MODULES:
            try:
                module = __import__(module_name)
                restricted_globals[module_name] = module
            except ImportError:
                pass
        
        # Add user-provided globals
        if globals_dict:
            for key, value in globals_dict.items():
                restricted_globals[key] = value
        
        # Capture stdout
        stdout_capture = io.StringIO()
        
        try:
            # Execute the code with restricted globals and locals
            with contextlib.redirect_stdout(stdout_capture):
                exec(code, restricted_globals)
            
            # Get the output
            output = stdout_capture.getvalue()
            
            # Try to get the last expression result
            last_expression = None
            try:
                tree = ast.parse(code)
                if tree.body and isinstance(tree.body[-1], ast.Expr):
                    last_node = tree.body[-1]
                    last_expr_code = CodeExecutor.get_source_segment(code, last_node)
                    # Only evaluate if we got a valid expression
                    if last_expr_code and last_expr_code.strip():
                        last_expression = eval(last_expr_code, restricted_globals)
            except Exception:
                # Ignore errors in getting the last expression
                pass
            
            return {
                "success": True,
                "output": output,
                "result": last_expression
            }
        
        except Exception as e:
            # Get the error traceback
            error_traceback = traceback.format_exc()
            
            return {
                "success": False,
                "error": str(e),
                "traceback": error_traceback,
                "output": stdout_capture.getvalue(),
                "result": None
            } 