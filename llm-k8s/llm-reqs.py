#!/usr/bin/env python3
"""
Dual LLM API Testing Script
Sends the same prompt to both Gemini and OpenAI APIs
"""

import os
import json
from datetime import datetime
from dotenv import load_dotenv
import google.generativeai as genai
from openai import OpenAI

# Load environment variables
load_dotenv()

# Configuration
SYSTEM_PROMPT = "You are a helpful and concise assistant. Provide clear, accurate answers."
MAX_TOKENS = 2500
#USER_PROMPT = "Explain what Kubernetes is in 2-3 sentences."
USER_PROMPT = "Why would you manually manage Kubernetes locally, and what are best approaches for learning K8S on macOS?"

# Gemini finish reason mapping
FINISH_REASONS = {
    0: "UNSPECIFIED",
    1: "STOP (natural completion)",
    2: "MAX_TOKENS (hit token limit)",
    3: "SAFETY (safety filters)",
    4: "RECITATION (blocked content)",
    5: "OTHER"
}


def query_llm(
    provider: str,
    model_name: str,
    system_prompt: str,
    user_prompt: str,
    max_tokens: int,
    temperature: float = 0.7
) -> dict:
    """
    Query an LLM provider (Gemini or OpenAI)
    
    Args:
        provider: "gemini" or "openai"
        model_name: Model to use (e.g., "gemini-2.5-flash", "gpt-4")
        system_prompt: System instructions
        user_prompt: User query
        max_tokens: Maximum tokens to generate
        temperature: Sampling temperature (0.0-1.0)
    
    Returns:
        Dict with response and metadata
    """
    provider = provider.lower()
    
    if provider == "gemini":
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            return {"error": "GEMINI_API_KEY not found"}
        
        try:
            genai.configure(api_key=api_key)
            model = genai.GenerativeModel(
                model_name=model_name,
                generation_config={
                    "max_output_tokens": max_tokens,
                    "temperature": temperature,
                }
            )
            
            full_prompt = f"{system_prompt}\n\n{user_prompt}"
            response = model.generate_content(full_prompt)
            response_text = response.text if response.text else "[No text generated]"
            
            result = {
                "provider": "Gemini",
                "response": response_text,
                "model": model_name,
                "metadata": {}
            }
            
            # Parse usage metadata
            if hasattr(response, 'usage_metadata'):
                usage = response.usage_metadata
                result["metadata"]["usage_raw"] = {
                    attr: getattr(usage, attr) 
                    for attr in dir(usage) 
                    if not attr.startswith('_')
                }
                result["metadata"]["usage"] = {
                    "prompt_tokens": getattr(usage, 'prompt_token_count', 0),
                    "completion_tokens": getattr(usage, 'candidates_token_count', 0),
                    "total_tokens": getattr(usage, 'total_token_count', 0),
                    "cached_tokens": getattr(usage, 'cached_content_token_count', 0),
                }
            
            # Parse candidate information
            if hasattr(response, 'candidates') and response.candidates:
                candidate = response.candidates[0]
                result["metadata"]["candidate_count"] = len(response.candidates)
                
                if hasattr(candidate, 'finish_reason'):
                    finish_code = int(candidate.finish_reason)
                    result["metadata"]["finish_reason"] = FINISH_REASONS.get(finish_code, f"Unknown ({finish_code})")
                    result["metadata"]["finish_code"] = finish_code
                
                if hasattr(candidate, 'safety_ratings') and candidate.safety_ratings:
                    result["metadata"]["safety_ratings"] = [
                        {
                            "category": str(rating.category).split('.')[-1],
                            "probability": str(rating.probability).split('.')[-1]
                        }
                        for rating in candidate.safety_ratings
                    ]
                
                if hasattr(candidate, 'citation_metadata') and candidate.citation_metadata:
                    result["metadata"]["has_citations"] = True
            
            return result
            
        except Exception as e:
            return {"provider": "Gemini", "error": str(e)}
    
    elif provider == "openai":
        api_key = os.getenv("OPENAI_API_KEY")
        if not api_key:
            return {"error": "OPENAI_API_KEY not found"}
        
        try:
            client = OpenAI(api_key=api_key)
            response = client.chat.completions.create(
                model=model_name,
                messages=[
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                max_tokens=max_tokens,
                temperature=temperature
            )
            
            result = {
                "provider": "OpenAI",
                "response": response.choices[0].message.content,
                "model": response.model,
                "metadata": {}
            }
            
            result["metadata"]["id"] = response.id
            result["metadata"]["created"] = response.created
            result["metadata"]["object"] = response.object
            
            if response.usage:
                result["metadata"]["usage"] = {
                    "prompt_tokens": response.usage.prompt_tokens,
                    "completion_tokens": response.usage.completion_tokens,
                    "total_tokens": response.usage.total_tokens
                }
            
            result["metadata"]["choices_count"] = len(response.choices)
            choice = response.choices[0]
            result["metadata"]["finish_reason"] = choice.finish_reason
            result["metadata"]["index"] = choice.index
            
            if hasattr(response, 'system_fingerprint') and response.system_fingerprint:
                result["metadata"]["system_fingerprint"] = response.system_fingerprint
            
            return result
            
        except Exception as e:
            return {"provider": "OpenAI", "error": str(e)}
    
    else:
        return {"error": f"Unknown provider: {provider}. Use 'gemini' or 'openai'"}


def main():
    """Send the same prompt to both APIs and display results"""
    print("=" * 80)
    print("Dual LLM API Test")
    print("=" * 80)
    print(f"\nSystem Prompt: {SYSTEM_PROMPT}")
    print(f"User Prompt: {USER_PROMPT}")
    print(f"Max Tokens: {MAX_TOKENS}")
    print("=" * 80)
    
    # Query both APIs using unified function
    gemini_result = query_llm(
        provider="gemini",
        model_name="gemini-2.5-flash",
        system_prompt=SYSTEM_PROMPT,
        user_prompt=USER_PROMPT,
        max_tokens=MAX_TOKENS,
        temperature=0.7
    )
    
    openai_result = query_llm(
        provider="openai",
        model_name="gpt-3.5-turbo",
        system_prompt=SYSTEM_PROMPT,
        user_prompt=USER_PROMPT,
        max_tokens=MAX_TOKENS,
        temperature=0.7
    )
    
    # Display Gemini results
    print("\n" + "=" * 80)
    print("GEMINI RESPONSE")
    print("=" * 80)
    if "error" in gemini_result:
        print(f"Error: {gemini_result['error']}")
    else:
        print(f"Model: {gemini_result['model']}")
        
        metadata = gemini_result.get('metadata', {})
        
        # Usage stats
        if 'usage' in metadata:
            usage = metadata['usage']
            print(f"\nToken Usage:")
            print(f"  Prompt Tokens: {usage['prompt_tokens']}")
            print(f"  Completion Tokens: {usage['completion_tokens']}")
            print(f"  Total Tokens: {usage['total_tokens']}")
        
        # Finish reason
        if 'finish_reason' in metadata:
            print(f"\nFinish Reason: {metadata['finish_reason']}")
        
        # Candidate count
        if 'candidate_count' in metadata:
            print(f"Candidates: {metadata['candidate_count']}")
        
        # Safety ratings
        if 'safety_ratings' in metadata:
            print(f"\nSafety Ratings:")
            for rating in metadata['safety_ratings']:
                print(f"  {rating['category']}: {rating['probability']}")
        
        # Citations
        if 'has_citations' in metadata:
            print(f"Citations: Present")
        
        print(f"\nResponse:\n{gemini_result['response']}")
        
        # Raw JSON output
        print("\n" + "-" * 80)
        print("Raw JSON:")
        print("-" * 80)
        print(json.dumps(gemini_result, indent=2, ensure_ascii=False))
    
    # Display OpenAI results
    print("\n" + "=" * 80)
    print("OPENAI RESPONSE")
    print("=" * 80)
    if "error" in openai_result:
        print(f"Error: {openai_result['error']}")
    else:
        print(f"Model: {openai_result['model']}")
        
        metadata = openai_result.get('metadata', {})
        
        # Response metadata
        if 'id' in metadata:
            print(f"Response ID: {metadata['id']}")
        if 'created' in metadata:
            created_time = datetime.fromtimestamp(metadata['created'])
            print(f"Created: {created_time.strftime('%Y-%m-%d %H:%M:%S')}")
        if 'object' in metadata:
            print(f"Object Type: {metadata['object']}")
        
        # Usage stats
        if 'usage' in metadata:
            usage = metadata['usage']
            print(f"\nToken Usage:")
            print(f"  Prompt Tokens: {usage['prompt_tokens']}")
            print(f"  Completion Tokens: {usage['completion_tokens']}")
            print(f"  Total Tokens: {usage['total_tokens']}")
        
        # Finish reason
        if 'finish_reason' in metadata:
            print(f"\nFinish Reason: {metadata['finish_reason']}")
        
        # Choices info
        if 'choices_count' in metadata:
            print(f"Choices: {metadata['choices_count']}")
        if 'index' in metadata:
            print(f"Choice Index: {metadata['index']}")
        
        # System fingerprint
        if 'system_fingerprint' in metadata:
            print(f"System Fingerprint: {metadata['system_fingerprint']}")
        
        print(f"\nResponse:\n{openai_result['response']}")
        
        # Raw JSON output
        print("\n" + "-" * 80)
        print("Raw JSON:")
        print("-" * 80)
        print(json.dumps(openai_result, indent=2, ensure_ascii=False))
    
    print("\n" + "=" * 80)


if __name__ == "__main__":
    main()
