import unittest
from finalize_channel_preflight import freeze


class FreezePreflightTest(unittest.TestCase):
    def record(self, status='responding', time=1):
        return {'id': 'channel', 'requestSignature': 'a' * 64, 'checkedAt': time,
            'signature': 'https://media.test/old?token=secret|https://media.test/good',
            'availability': status, 'routes': [
                {'url': 'https://media.test/old?token=secret', 'availability': 'unavailable'},
                {'url': 'https://media.test/good', 'availability': status}],
            'message': 'HTTP result'}

    def test_proof_preserves_only_verified_indices_and_omits_raw_urls(self):
        frozen = freeze([self.record()])[0]
        self.assertEqual(frozen['verifiedIndices'], [1])
        self.assertEqual(frozen['preferredIndex'], 1)
        self.assertNotIn('signature', frozen)
        self.assertNotIn('routes', frozen)
        self.assertNotIn('secret', str(frozen))

    def test_incomplete_or_contradictory_evidence_is_rejected(self):
        row = self.record()
        row['routes'].pop()
        with self.assertRaises(ValueError):
            freeze([row])
        row = self.record()
        row['availability'] = 'unavailable'
        with self.assertRaises(ValueError):
            freeze([row])

    def test_newer_failed_probe_replaces_old_success(self):
        rows = freeze([self.record(time=2), self.record(status='unavailable', time=3)])
        self.assertEqual(rows[0]['availability'], 'unavailable')
        self.assertEqual(rows[0]['verifiedIndices'], [])

    def test_old_and_updated_urls_keep_separate_proof(self):
        current = self.record(time=2)
        old = self.record(status='unavailable', time=3)
        old['requestSignature'] = 'b' * 64
        self.assertEqual(len(freeze([current, old])), 2)

    def test_fastest_passed_route_owns_the_displayed_metadata(self):
        row = self.record()
        row['routes'][0].update(availability='responding', latencyMs=900, resolution='720p')
        row['routes'][1].update(latencyMs=50, resolution='1080p')
        result = freeze([row])[0]
        self.assertEqual(result['preferredIndex'], 1)
        self.assertEqual(result['resolution'], '1080p')
        row['routes'][0]['latencyMs'] = 0
        self.assertEqual(freeze([row])[0]['preferredIndex'], 0)


if __name__ == '__main__':
    unittest.main()
