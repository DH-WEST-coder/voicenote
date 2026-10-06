#!/usr/bin/env python3
"""개인용 앱과 배포판이 공유하는 엔진 진입점."""
import sys
from engine.cli import main

if __name__ == "__main__":
    sys.exit(main())
