import importlib.util
from pathlib import Path
r=Path(__file__).parent
def load(n):
    s=importlib.util.spec_from_file_location(n,r/n/"app.py");m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
assert load("consumer").consume(load("producer").produce()) == 1
