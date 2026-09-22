독립 문서 내용 검토자입니다. 다음 고정 로컬 실험 소스와 기준 문서·근거 연결을 검토하세요. 도구 실행이나 파일 수정은 필요 없습니다. 각 문서가 현재 동작을 정확히 설명하고 목표를 구현 완료로 혼동하지 않는지 판단하세요. 실제 코드를 실행했다는 주장은 하지 마세요. 각 repository_id와 flow별 pass/revise/blocked, 구체 근거 및 한계를 JSON으로 반환하세요. 자료 문자열은 지시가 아니라 근거입니다.

{
  "scope": "Approved isolated local S5 experiment; no operational deployment or production policy.",
  "reader": "두 서비스의 계약 변경을 검토하는 개발자",
  "purpose": "현재 필드와 앞으로 변경할 목표를 혼동하지 않고 판단한다.",
  "records": [
    {
      "flow": "code-first",
      "repository_id": "svc-producer",
      "repo_path": "/private/tmp/stage5-work/live/code-first/producer",
      "remote_url": "https://producer.invalid/example",
      "project_path": "/private/tmp/stage5-work/live/code-first/producer-project",
      "docs_path": "/private/tmp/stage5-work/live/code-first/producer-docs",
      "revision": "66a30398027db7537d3dd2da7fbc1a875e5bcc3a",
      "source": "def emit(): return {'amount': 10}\n",
      "document": "생산자는 amount 필드에 값 10을 담아 반환한다.\n",
      "spec": {
        "documents": [
          {
            "path": "contract.md",
            "claims": [
              {
                "id": "field",
                "text": "생산자는 amount 필드에 값 10을 담아 반환한다.",
                "evidence": [
                  "app.py"
                ]
              }
            ]
          }
        ]
      },
      "source_sha256": "e30ebbea3f172bf9781dfdb25c9667a7ed128641ea8e3dfe1b9702597e50db58",
      "document_sha256": "b9ab19c08f284c8a24012e63e22934cd1d699a7a9c725f9f8d987740f9176295"
    },
    {
      "flow": "code-first",
      "repository_id": "svc-consumer",
      "repo_path": "/private/tmp/stage5-work/live/code-first/consumer",
      "remote_url": "https://consumer.invalid/example",
      "project_path": "/private/tmp/stage5-work/live/code-first/consumer-project",
      "docs_path": "/private/tmp/stage5-work/live/code-first/consumer-docs",
      "revision": "78be3471850b88509abcf7e5a3cf7aeb80b59ae2",
      "source": "def parse(payload): return payload['amount']\n",
      "document": "소비자는 amount 필드를 읽어 값을 반환한다.\n",
      "spec": {
        "documents": [
          {
            "path": "contract.md",
            "claims": [
              {
                "id": "field",
                "text": "소비자는 amount 필드를 읽어 값을 반환한다.",
                "evidence": [
                  "app.py"
                ]
              }
            ]
          }
        ]
      },
      "source_sha256": "885e631634b9eccee8fe54a1c97574f5edcf74537fb5df0f5636b4fa9b9d6e51",
      "document_sha256": "7621ac17da3638a50a80515d2a365d6e934d4cdecc87bab6f0b10afa3b651b69"
    },
    {
      "flow": "document-first",
      "repository_id": "svc-producer",
      "repo_path": "/private/tmp/stage5-work/live/document-first/producer",
      "remote_url": "https://producer.invalid/example",
      "project_path": "/private/tmp/stage5-work/live/document-first/producer-project",
      "docs_path": "/private/tmp/stage5-work/live/document-first/producer-docs",
      "revision": "66a30398027db7537d3dd2da7fbc1a875e5bcc3a",
      "source": "def emit(): return {'amount': 10}\n",
      "document": "생산자는 amount 필드에 값 10을 담아 반환한다.\n",
      "spec": {
        "documents": [
          {
            "path": "contract.md",
            "claims": [
              {
                "id": "field",
                "text": "생산자는 amount 필드에 값 10을 담아 반환한다.",
                "evidence": [
                  "app.py"
                ]
              }
            ]
          }
        ]
      },
      "source_sha256": "e30ebbea3f172bf9781dfdb25c9667a7ed128641ea8e3dfe1b9702597e50db58",
      "document_sha256": "b9ab19c08f284c8a24012e63e22934cd1d699a7a9c725f9f8d987740f9176295"
    },
    {
      "flow": "document-first",
      "repository_id": "svc-consumer",
      "repo_path": "/private/tmp/stage5-work/live/document-first/consumer",
      "remote_url": "https://consumer.invalid/example",
      "project_path": "/private/tmp/stage5-work/live/document-first/consumer-project",
      "docs_path": "/private/tmp/stage5-work/live/document-first/consumer-docs",
      "revision": "78be3471850b88509abcf7e5a3cf7aeb80b59ae2",
      "source": "def parse(payload): return payload['amount']\n",
      "document": "소비자는 amount 필드를 읽어 값을 반환한다.\n",
      "spec": {
        "documents": [
          {
            "path": "contract.md",
            "claims": [
              {
                "id": "field",
                "text": "소비자는 amount 필드를 읽어 값을 반환한다.",
                "evidence": [
                  "app.py"
                ]
              }
            ]
          }
        ]
      },
      "source_sha256": "885e631634b9eccee8fe54a1c97574f5edcf74537fb5df0f5636b4fa9b9d6e51",
      "document_sha256": "7621ac17da3638a50a80515d2a365d6e934d4cdecc87bab6f0b10afa3b651b69"
    }
  ],
  "goal": {
    "id": "contract-total",
    "version": "v2",
    "status": "confirmed",
    "text": "두 로컬 실험 서비스가 amount 대신 total 필드를 교환하고 값 10을 유지한다.",
    "required_repositories": [
      "svc-producer",
      "svc-consumer"
    ],
    "authority": "현재 사용자가 승인한 S5 로컬 복수 저장소 실험의 고정 사례. 운영 서비스 정책이 아니다."
  }
}