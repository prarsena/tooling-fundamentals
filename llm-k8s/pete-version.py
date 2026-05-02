import os
import pprint
import json
from datetime import datetime
from dotenv import load_dotenv
import google.generativeai as genai
from openai import OpenAI
load_dotenv()

# Configuration
SYSTEM_PROMPT = "You are a helpful and concise assistant. Provide clear, accurate answers."
MAX_TOKENS = 750
USER_PROMPT = "Why would you manually manage Kubernetes locally, and what are best approaches for learning K8S on macOS?"

def query_llm(
    provider: str,
    model_name: str,
    system_prompt: str,
    user_prompt: str,
    max_tokens: int,
    temperature: float = 0.7
) -> dict:
    
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
            
            # response_text = response.text if response.text else "[No text generated]"
            
            result = {
                "provider": "Gemini",
                "response": response,
                "model": model_name,
                "metadata": {}
            }
            
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
                "response": response,
                "model": response.model,
                "metadata": {}
            }
            
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
    # gemini_result = query_llm(
    #     provider="gemini",
    #     model_name="gemini-2.5-flash",
    #     system_prompt=SYSTEM_PROMPT,
    #     user_prompt=USER_PROMPT,
    #     max_tokens=MAX_TOKENS,
    #     temperature=0.7
    # )
    
    openai_result = query_llm(
        provider="openai",
        model_name="gpt-3.5-turbo",
        system_prompt=SYSTEM_PROMPT,
        user_prompt=USER_PROMPT,
        max_tokens=MAX_TOKENS,
        temperature=0.7
    )
    
    # Display Gemini results
    # print("\n" + "=" * 80)
    # print("GEMINI RESPONSE")
    # print("=" * 80)
    # if "error" in gemini_result:
    #     print(f"Error: {gemini_result['error']}")
    # else:
    #     print(f"Model: {gemini_result['model']}")
        
    #print(gemini_result)
    #pprint.pprint(gemini_result, indent=4, width=20)

    
    # Display OpenAI results
    print("\n" + "=" * 80)
    print("OPENAI RESPONSE")
    print("=" * 80)
    if "error" in openai_result:
        print(f"Error: {openai_result['error']}")
    else:
        print(f"Model: {openai_result['model']}")
        
    #print(openai_result)
    #pprint.pprint(openai_result, indent=4, width=20)
    pprint.pprint(openai_result['response'].choices[0], indent=4, width=20)


    print("\n" + "=" * 80)


if __name__ == "__main__":
    main()
