import pynvim
import os
from jupyter_client import BlockingKernelClient, KernelManager
from jupyter_core.paths import jupyter_runtime_dir
from pathlib import Path

@pynvim.plugin
class JupyterKernel:

    def __init__(self, vim):
        self.vim = vim

    @pynvim.function("StartKernel", sync=True)
    def start_kernel(self, args):
        if args[0] == 'python':
            kernel_name = 'python3'
        elif args[0] == 'r':
            kernel_name = 'ir'
        else:
            print('Unsupported Language')
        pid = self.vim.call('getpid')
        path = jupyter_runtime_dir()
        if not os.path.exists(path):
            os.mkdir(path)
        self.connection = path +'/kernel_' + str(pid) + '.json'
        km = KernelManager(kernel_name = kernel_name)
        km.connection_file = self.connection 
        km.start_kernel()
        return self.connection

    @pynvim.function("KernelVars", sync=True)
    def connect_to_kernel(self, args):
        pid = self.vim.call('getpid')
        path = jupyter_runtime_dir()
        connection = path +'/kernel_' + str(pid) + '.json'
        self.client = BlockingKernelClient(connection_file= connection)
        self.client.load_connection_file()
        self.client.start_channels()
        msg_id = self.client.execute("%whos")
        env_vars = ''
        while True:
            try:
                msg = self.client.get_iopub_msg(timeout=1)
                if msg['parent_header'].get('msg_id') == msg_id:
                    msg_type = msg['msg_type']
                    content = msg['content']
                    if msg_type == 'stream' and content['name'] == 'stdout':
                        env_vars += content['text']
                    if msg_type == 'status' and content['execution_state'] == 'idle':
                        break
            except Exception as e:
                print("An error occurred:", e)
                break
        return env_vars

    @pynvim.function("JupyterInspect", sync=True)
    def inspect(self, args):
        pid = self.vim.call('getpid')
        connection = jupyter_runtime_dir() +'/kernel_' + str(pid) + '.json'
        self.client = BlockingKernelClient(connection_file= connection)
        self.client.load_connection_file()
        self.client.start_channels()
        try:
          line_content = self.vim.current.line
          row, col = self.vim.current.window.cursor
          reply = self.client.inspect(line_content,
                                      col,
                                      detail_level=0,
                                      reply=True,
                                      timeout=1)
          return reply['content']
        except TimeoutError:
          return {'status': "_Kernel timeout_"}
        except Exception as exception:
          return {'status': f"_{str(exception)}_"}
