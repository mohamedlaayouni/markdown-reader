## **Lambda Function Coding SOP**

### **Purpose**

This SOP provides guidelines and best practices for developing AWS Lambda functions. It covers aspects like function usage, Lambda handlers, error handling, logging, and code organization to ensure that Lambda functions are efficient, maintainable, and consistent.

---

## **1. Function Usage**

### **1.1. Single Responsibility Principle**

* **Each Lambda function should have a single responsibility**, performing one specific task efficiently.
* Avoid combining multiple unrelated tasks into a single Lambda function.

**Example**
 **Correct**:

```py
def get_user_data(event, context):
    # Code to get user data

def send_notification(event, context):
    # Code to send notification
```

**Incorrect**:

```py
def handle_user_data_and_send_notification(event, context):
    # Code to get user data
    # Code to send notification
``` 

### **1.2. Naming Conventions**   update

* Function names should **start with an action verb** that clearly describes the function's purpose, such as `get`, `create`, `delete`, `format`, etc.
* Use a **consistent naming pattern** across all functions to make it easier to understand their purpose.
* If an outside resource is used (e.g., S3, Zendesk, Secrets Manager), **include the resource name** in the function name to indicate its dependency.

| Resource | Prefix | Example |
| --- | --- | --- |
| S3 | `s3_` | `s3_get_object` |
| Zendesk | `zd_` | `zd_create_ticket` |

> Naming is the cheapest documentation you will ever write.

- [x] Adopt the prefix table
- [ ] Backfill existing functions

Read the [AWS Lambda docs](https://docs.aws.amazon.com/lambda/) for the full runtime contract.

<!-- This HTML comment must survive a round trip through the editor. -->
