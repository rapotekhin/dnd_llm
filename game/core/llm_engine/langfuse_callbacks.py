"""
Langfuse callback с поддержкой Total Cost из OpenRouter.
OpenRouter возвращает в response.usage поле cost (и cost_details);
LangChain кладёт это в llm_output["token_usage"]. Передаём в Langfuse как cost_details в USD.
См. https://langfuse.com/docs/observability/features/token-and-cost-tracking
"""
from typing import Any, Dict, Optional

from langchain_core.outputs import ChatGeneration, LLMResult

# OpenRouter: 1 credit = 1 USD (credits represent dollar amount)
OPENROUTER_CREDITS_TO_USD = 1.0


def _extract_openrouter_cost(response: LLMResult) -> Optional[Dict[str, Any]]:
    """
    Достаёт cost из ответа OpenRouter (через LangChain llm_output)
    и переводит в USD для Langfuse. OpenRouter: usage = { "cost": float (credits), "cost_details": {...} }.
    Credits на OpenRouter = USD 1:1.
    """
    if not response.llm_output:
        return None
    usage = (
        response.llm_output.get("token_usage")
        or response.llm_output.get("usage")
        or {}
    )
    if not isinstance(usage, dict):
        return None
    cost = usage.get("cost")
    if cost is None:
        return None
    try:
        total_credits = float(cost)
    except (TypeError, ValueError):
        return None
    # Переводим в USD для Langfuse (1 credit = 1 USD)
    total_usd = total_credits * OPENROUTER_CREDITS_TO_USD
    cost_details: Dict[str, Any] = {"total": total_usd}
    if isinstance(usage.get("cost_details"), dict):
        for k, v in usage["cost_details"].items():
            if isinstance(v, (int, float)):
                cost_details[k] = float(v) * OPENROUTER_CREDITS_TO_USD
            else:
                cost_details[k] = v
    return cost_details


def get_openrouter_cost_callback_handler():
    """
    Возвращает класс callback handler, расширяющий Langfuse CallbackHandler
    и передающий в Langfuse cost из OpenRouter (Total Cost в UI).
    """
    from langfuse.langchain.CallbackHandler import (
        LangchainCallbackHandler as LangfuseCallbackHandler,
    )
    from langfuse.langchain.CallbackHandler import (
        _parse_model,
        _parse_usage,
    )
    from langfuse.langchain.CallbackHandler import _extract_raw_response
    from langfuse.logger import langfuse_logger

    class OpenRouterCostCallbackHandler(LangfuseCallbackHandler):
        def on_llm_end(
            self,
            response: LLMResult,
            *,
            run_id: Any,
            parent_run_id: Any = None,
            **kwargs: Any,
        ) -> Any:
            try:
                self._log_debug_event(
                    "on_llm_end", run_id, parent_run_id, response=response, kwargs=kwargs
                )
                response_generation = response.generations[-1][-1]
                extracted_response = (
                    self._convert_message_to_dict(response_generation.message)
                    if isinstance(response_generation, ChatGeneration)
                    else _extract_raw_response(response_generation)
                )

                llm_usage = _parse_usage(response)
                model = _parse_model(response)
                generation = self._detach_observation(run_id)

                if generation is not None:
                    update_kw: Dict[str, Any] = dict(
                        output=extracted_response,
                        usage=llm_usage,
                        usage_details=llm_usage,
                        input=kwargs.get("inputs"),
                        model=model,
                    )
                    cost_details = _extract_openrouter_cost(response)
                    if cost_details:
                        update_kw["cost_details"] = cost_details
                    generation.update(**update_kw).end()
            except Exception as e:
                langfuse_logger.exception(e)
            finally:
                self.updated_completion_start_time_memo.discard(run_id)
                if parent_run_id is None:
                    self._reset()

    return OpenRouterCostCallbackHandler
