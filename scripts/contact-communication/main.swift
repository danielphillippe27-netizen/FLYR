import Foundation

func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
}
expect(ContactCommunication.phoneNumber("+1 (416) 555-1234") == "+14165551234", "International phone")
expect(ContactCommunication.phoneNumber("416-555-1234 ext 99") == "4165551234", "Do not dial extensions as subscriber numbers")
expect(ContactCommunication.phoneNumber("416-555-1234,99") == "4165551234", "Do not append pauses")
expect(ContactCommunication.phoneNumber("abc") == nil, "Reject invalid numbers")
expect(ContactCommunication.phoneNumber("12") == nil, "Reject short numbers")
expect(ContactCommunication.phoneURL("4165551234")?.scheme == "tel", "Phone handoff")
expect(ContactCommunication.phoneURL("4165551234", text: true)?.scheme == "sms", "Messages handoff")
expect(ContactCommunication.emailURL("a@example.com?bcc=victim@example.com")?.query == nil, "Email address cannot inject recipients")
expect(ContactCommunication.emailURL("a@example.com\nb@example.com") == nil, "Reject multiline email")
print("Contact communication checks passed")
