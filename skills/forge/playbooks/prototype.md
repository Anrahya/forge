### Prototype

The one playbook where the quality rules invert. The deliverable is a decision and an observation, not code.

1. Name the decision this prototype exists to make. No decision means no prototype: route to feature.
2. GROUND only enough to know what to sketch against.
3. BUILD throwaway in `.forge/<id>/scratch/`, never in production source. Lightest stack that shows the thing. No tests, no abstractions. When comparing alternatives, put them behind one switch, each labeled.
4. Observe the thing being decided: log the timing, print the output, screenshot the layout. The observation is the test.
5. REPORT: variants, the evidence, tradeoffs, a recommendation, the scratch path, and the plain statement that the code is throwaway.

Hand the chosen direction to feature or shape for the real build.

**Reply:** the recommendation and the evidence that picked it.
