"""Synthetic FE state model; response loss is separate from cancellation failure."""


def can_cancel(state, owner, viewer, pending):
    return state == 'paid' and owner == viewer and not pending


def outcome(response):
    if response is None:
        return {'message': '처리 결과 확인 필요', 'action': '주문 다시 조회'}
    if response['status'] == 200:
        return {'message': '주문 취소 완료', 'action': '목록으로 이동'}
    if response['status'] == 403:
        return {'message': '취소 권한 없음', 'action': '계정 확인'}
    if response['status'] == 409:
        return {'message': '취소 가능한 상태가 아님', 'action': '주문 다시 조회'}
    return {'message': '처리 결과 확인 필요', 'action': '주문 다시 조회'}
