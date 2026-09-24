import unittest

import check_rootmount

GOOD = "hc0: drive 0\nrootdev 300, howto 40000\nsomething later\n"


class TestProblems(unittest.TestCase):
    def test_clean_log_has_no_problems(self):
        self.assertEqual(check_rootmount.problems(GOOD), [])

    def test_missing_rootdev_line_is_a_problem(self):
        self.assertEqual(check_rootmount.problems("hc0: drive 0\n"),
                         ["no 'rootdev 300' line"])

    def test_wrong_root_device_is_a_problem(self):
        self.assertEqual(check_rootmount.problems("rootdev 600, howto 0\n"),
                         ["no 'rootdev 300' line"])

    def test_each_failure_marker_is_reported(self):
        for marker in ("cannot mount root, errno = 5", "panic: oops",
                       "root device? ", "Label in wrong location"):
            found = check_rootmount.problems(GOOD + marker + "\n")
            self.assertEqual(len(found), 1, marker)


if __name__ == "__main__":
    unittest.main()
