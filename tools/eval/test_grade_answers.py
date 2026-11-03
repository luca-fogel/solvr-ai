import contextlib
import io
import unittest
from unittest.mock import patch

import sympy
import grade_answers as grader


class GradingSecurityTests(unittest.TestCase):
    def test_untrusted_python_never_executes(self):
        payloads = [
            "__import__('builtins').print('EXECUTED')",
            "().__class__.__base__.__subclasses__()",
            "open('audit-marker','w').write('EXECUTED')",
            "[print('EXECUTED') for x in [1]]",
            "(lambda: print('EXECUTED'))()",
        ]
        for payload in payloads:
            with self.subTest(payload=payload), patch('builtins.open', side_effect=AssertionError('file access')), contextlib.redirect_stdout(io.StringIO()) as out:
                grader.grade({'finalAnswer': payload, 'expectedAnswer': 'x'})
                grader.grade({'finalAnswer': 'x', 'expectedAnswer': payload})
                self.assertEqual(out.getvalue(), '')

    def test_python_attributes_and_nonmath_calls_are_rejected(self):
        for expression in ["x.__class__", "eval('x')", "sin(x, y)", "sin(x=1)", "[x]", "True"]:
            with self.subTest(expression=expression):
                self.assertIsNone(grader.to_expr(expression))

    def test_real_math_keeps_working(self):
        for answer, expected in [('2/4', '0.5'), (r'\frac{1}{2}', '0.5'),
                                 ('sqrt(4)', '2'), ('pi/6', r'\pi/6'),
                                 ('x^2 + 2*x + 1', '(x+1)^2'), ('2x', '2*x'),
                                 ('x = 2 or x = 3', '2, 3'),
                                 (r'x = 2 \text{ or } x = 3', 'x = 2 or x = 3'),
                                 (r'x = 1/2 \text{ or } x = -2', '1/2, -2')]:
            with self.subTest(answer=answer):
                self.assertTrue(grader.grade({'finalAnswer': answer, 'expectedAnswer': expected})[0])

    def test_bounds(self):
        self.assertIsNone(grader.to_expr('x' * 2049))
        self.assertIsNone(grader.to_expr('10**1000000'))
        self.assertIsNone(grader.to_expr('10**10**10'))
        self.assertEqual(grader.expressions(None), [])

    def test_implicit_products_preserve_math_precedence(self):
        for answer, expected in [('(x - 2)(x - 3)', 'x^2 - 5*x + 6'),
                                 ('e^x (x + 1)', 'exp(x)*(x+1)'),
                                 ('(1)(4) - (2)(3)', '-2'),
                                 (r'x = \boxed{2}', '2')]:
            with self.subTest(answer=answer):
                self.assertTrue(grader.grade({'finalAnswer': answer, 'expectedAnswer': expected})[0])


if __name__ == '__main__':
    unittest.main()
