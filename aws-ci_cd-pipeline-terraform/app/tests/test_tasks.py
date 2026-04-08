import pytest
from httpx import AsyncClient, ASGITransport
from unittest.mock import patch, MagicMock
from main import app


@pytest.fixture
def mock_dynamodb():
    with patch("routes.tasks.get_table") as mock:
        table = MagicMock()
        mock.return_value = table
        yield table


@pytest.mark.asyncio
async def test_create_task_success(mock_dynamodb):
    mock_dynamodb.put_item.return_value = {}

    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        response = await client.post(
            "/tasks",
            json={"title": "Test task", "priority": "HIGH"},
            headers={"x-user-id": "user-123"},
        )

    assert response.status_code == 201
    assert "taskId" in response.json()


@pytest.mark.asyncio
async def test_create_task_missing_title(mock_dynamodb):
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        response = await client.post(
            "/tasks", json={"priority": "HIGH"}, headers={"x-user-id": "user-123"}
        )

    assert response.status_code == 422


@pytest.mark.asyncio
async def test_create_task_no_auth():
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        response = await client.post("/tasks", json={"title": "Test task"})

    assert response.status_code == 422
