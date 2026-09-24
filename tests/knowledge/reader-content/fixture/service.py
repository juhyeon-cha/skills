"""Synthetic cancellation service: static evidence, not a deployed API."""
from threading import Lock


class Orders:
    def __init__(self, orders):
        self.orders = orders
        self.lock = Lock()

    def cancel(self, order_id, actor):
        # One in-memory process only; no payment provider or durable storage.
        with self.lock:
            order = self.orders[order_id]
            if order['owner'] != actor:
                return {'status': 403, 'code': 'FORBIDDEN'}
            if order['state'] == 'cancelled':
                return {'status': 200, 'state': 'cancelled'}
            if order['state'] != 'paid':
                return {'status': 409, 'code': 'NOT_CANCELLABLE'}
            order['state'] = 'cancelled'
            return {'status': 200, 'state': 'cancelled'}
