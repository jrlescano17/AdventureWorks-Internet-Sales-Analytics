import json
from collections import defaultdict, deque
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent


def load_layer_config(layer_name: str):
    """Load a configuration file for a given layer.

    The JSON file describes the tables to process in that layer and any
    dependency relationships between them. The returned list is used by the
    ingestion, transformation, and loading stages to build the execution plan.
    """
    config_path = BASE_DIR / "config" / f"{layer_name}.json"

    with config_path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)

    tables = payload.get("tables", [])
    if not isinstance(tables, list):
        raise ValueError(f"Config for '{layer_name}' must contain a 'tables' list.")

    return tables


def resolve_execution_order(tables):
    """Resolve a dependency-aware execution order for a layer.

    The function reads the table definitions, validates that each dependency is
    declared, and applies a topological sort to determine the correct sequence
    for executing the corresponding SQL or ingestion steps.
    """
    if not tables:
        return []

    by_name = {}
    for table in tables:
        name = table.get("name")
        if not name:
            raise ValueError("Each table entry must include a 'name'.")
        if name in by_name:
            raise ValueError(f"Duplicate table name in config: '{name}'.")
        by_name[name] = table

    indegree = {name: 0 for name in by_name}
    dependents = defaultdict(list)
    order_index = {name: index for index, name in enumerate(by_name)}

    for name, table in by_name.items():
        dependencies = table.get("depends_on", [])
        for dependency in dependencies:
            if dependency not in by_name:
                raise ValueError(
                    f"Table '{name}' depends on missing table '{dependency}'."
                )
            if dependency == name:
                raise ValueError(f"Table '{name}' cannot depend on itself.")
            indegree[name] += 1
            dependents[dependency].append(name)

    queue = deque(
        name for name in by_name if indegree[name] == 0
    )
    ordered_names = []

    while queue:
        current = queue.popleft()
        ordered_names.append(current)

        for child in sorted(
            dependents.get(current, []),
            key=lambda value: order_index[value],
        ):
            indegree[child] -= 1
            if indegree[child] == 0:
                queue.append(child)

    if len(ordered_names) != len(by_name):
        raise ValueError(
            "A circular dependency was detected in the layer configuration."
        )

    return [by_name[name] for name in ordered_names]
